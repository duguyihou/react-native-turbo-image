// Nuke adapter (iOS). All Nuke code lives here, behind `TIImageLoading`
// (RFC rule 1). Only the ObjC entry point the registry finds by name is public.

import Foundation
import ImageIO
import Nuke
import NukeUI
import UIKit

// SwiftPM: the seam is a separate target. CocoaPods: same module.
#if canImport(TurboImageLoaderAPI)
  import TurboImageLoaderAPI
#endif

/// Cancellable handle that hides Nuke types.
private final class NukeLoadTask: NSObject, TIImageLoadTask, @unchecked Sendable {
  // Set once before being returned, then read-only: hence `@unchecked Sendable`.
  private let task: Task<Void, Never>
  private let progressTask: Task<Void, Never>?
  private let imageTask: ImageTask

  init(imageTask: ImageTask, task: Task<Void, Never>, progressTask: Task<Void, Never>?) {
    self.imageTask = imageTask
    self.task = task
    self.progressTask = progressTask
  }

  func cancel() {
    // Idempotent; cancelled Tasks drop their results.
    imageTask.cancel()
    task.cancel()
    progressTask?.cancel()
  }
}

/// The handle of a load that completed inside `loadImage`: nothing to cancel.
private final class FinishedTask: NSObject, TIImageLoadTask, @unchecked Sendable {
  func cancel() {}
}

/// Handle for `imageSize` and disk-only prefetch; cancel drops the result.
private final class AsyncTask: NSObject, TIImageLoadTask, @unchecked Sendable {
  private let task: Task<Void, Never>
  init(task: Task<Void, Never>) { self.task = task }
  func cancel() { task.cancel() }
}

@objc(TurboImageNukeLoader)
public final class NukeImageLoader: NSObject, TIImageLoading, @unchecked Sendable {
  // `ImagePipeline` is Sendable.
  /// Every policy but `urlCache`: disk tier is `DataCache` by `cacheKey`.
  /// Internal for tests.
  let pipeline: ImagePipeline
  /// `urlCache` requests (`TIImageRequest.httpCache`): disk tier = `urlCache`.
  private let httpPipeline: ImagePipeline
  /// The HTTP cache behind `httpPipeline`. Internal for tests.
  let urlCache: URLCache

  /// A non-original memory entry of a cache key (per processor and size).
  private struct Variant: Hashable {
    /// Nuke's processor identifier; empty if unprocessed.
    let processorID: String
    let thumbnail: ImageRequest.ThumbnailOptions?
  }

  // Variants per cache key, since Nuke's memory cache can't be enumerated.
  // Used by `removeCachedImage` and the `memoryCacheKey` placeholder. Locked:
  // read from any thread. Bounded by sweeping out entries Nuke evicted.
  private let variantsLock = NSLock()
  private var variants: [String: Set<Variant>] = [:]
  /// Total variants across keys. Read by tests.
  private(set) var variantCount = 0
  /// Sweep past this; reset to twice the survivors (amortized O(1) per load).
  private var sweepThreshold: Int
  private let minimumSweepThreshold: Int

  /// Must equal `DISK_CACHE_BYTES` on Android (CoilLoaderSetup.kt).
  static let diskCacheBytes = 150 * 1024 * 1024

  @objc public override convenience init() {
    self.init(minimumSweepThreshold: 512)
  }

  /// `minimumSweepThreshold` is lowered only by tests.
  init(minimumSweepThreshold: Int) {
    self.minimumSweepThreshold = minimumSweepThreshold
    sweepThreshold = minimumSweepThreshold
    // Own pipelines and caches, not Nuke's shared ones, so the host app's Nuke
    // use can't interfere (RFC rule 3, mirrors Coil): disk stores original
    // bytes, no HTTP caching, requests coalesced. Both pipelines share one
    // memory cache.
    let maxMemoryCost = TIImageLoaderRegistry.cacheMaxMemoryCost
    let diskBytes =
      TIImageLoaderRegistry.cacheMaxDiskSize > 0
      ? TIImageLoaderRegistry.cacheMaxDiskSize : Self.diskCacheBytes
    let imageCache =
      maxMemoryCost > 0 ? ImageCache(costLimit: maxMemoryCost) : ImageCache()
    // Shared too: a key names one image whatever the policy.
    let animations = AnimationSources()
    pipeline = Self.makePipeline(
      .withDataCache(name: "com.turboimage.DataCache", sizeLimit: diskBytes),
      imageCache: imageCache, animations: animations)

    // `urlCache` policy: a separate pipeline whose disk tier is a private
    // HTTP cache that honours `Cache-Control` (`DataCache` ignores freshness).
    // No memory capacity (`imageCache` has it). Responses over 5% of capacity
    // are not stored.
    let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    urlCache = URLCache(
      memoryCapacity: 0,
      // Not sized by `configureCache`.
      // TODO: an option of its own if apps need to size it.
      diskCapacity: Self.diskCacheBytes,
      directory: cachesDirectory?.appendingPathComponent("com.turboimage.URLCache", isDirectory: true))
    let sessionConfiguration = URLSessionConfiguration.default
    sessionConfiguration.urlCache = urlCache
    httpPipeline = Self.makePipeline(
      ImagePipeline.Configuration(dataLoader: DataLoader(configuration: sessionConfiguration)),
      imageCache: imageCache, animations: animations)
    super.init()
  }

  /// Shared setup; the pipelines differ only in disk tier.
  private static func makePipeline(
    _ base: ImagePipeline.Configuration, imageCache: ImageCache, animations: AnimationSources
  ) -> ImagePipeline {
    var configuration = base
    configuration.imageCache = imageCache
    configuration.isTaskCoalescingEnabled = true
    // Content-sniffed decoders (NukeDecoders.swift).
    configuration.makeImageDecoder = { TurboImageDecoders.make($0, animations: animations) }
    // `ContentDecoder` attaches animations itself (see `AnimationSources`).
    configuration.isAnimatedImageParsingEnabled = false
    // Skips decompression for SVG images (NukeDecoders.swift).
    return ImagePipeline(configuration: configuration, delegate: TurboImagePipelineDelegate())
  }

  private func pipeline(for request: TIImageRequest) -> ImagePipeline {
    request.httpCache ? httpPipeline : pipeline
  }

  public func loadImage(
    with request: TIImageRequest,
    progress: TIImageLoadProgress?,
    completion: @escaping TIImageLoadCompletion
  ) -> any TIImageLoadTask {
    let nukeRequest = Self.makeNukeRequest(from: request)
    // Read back from the Nuke request so the index matches Nuke's key.
    let processorID = nukeRequest.processors.first?.identifier ?? ""
    let variant =
      !processorID.isEmpty || nukeRequest.thumbnail != nil
      ? Variant(processorID: processorID, thumbnail: nukeRequest.thumbnail) : nil
    let cacheKey = request.cacheKey
    if let variant {
      // Before the load, so a concurrent `dispose` still finds it.
      remember(variant, of: cacheKey)
    }
    let pipeline = pipeline(for: request)

    // Complete memory hits synchronously, or a recycled cell flashes blank
    // for a frame. Previews don't count.
    if request.memoryCacheRead,
      let cached = pipeline.cache.cachedImage(for: nukeRequest, caches: .memory),
      !cached.isPreview
    {
      let animation = cached.animation.map {
        PlayableAnimation(source: $0, fitsView: nukeRequest.thumbnail != nil)
      }
      completion(cached.image, animation, true, nil)
      return FinishedTask()
    }

    let imageTask = pipeline.imageTask(with: nukeRequest)

    // Cancelled before completion on the same actor, so no progress lands after it.
    let progressTask: Task<Void, Never>? = progress.map { callback in
      let progressBox = UncheckedSendable(callback)
      return Task { @MainActor in
        for await update in imageTask.progress {
          if Task.isCancelled { break }
          progressBox.value(update.completed, update.total)
        }
      }
    }

    // Boxed: the ObjC block isn't provably Sendable; it only runs on main.
    let completionBox = UncheckedSendable(completion)
    let task = Task { @MainActor in
      do {
        let response = try await imageTask.response
        progressTask?.cancel()
        // Re-remember: a sweep during the load may have dropped it.
        // After cancel, drop the result (seam contract).
        if let variant { self.remember(variant, of: cacheKey) }
        guard !Task.isCancelled else { return }
        let animation = response.container.animation.map {
          PlayableAnimation(source: $0, fitsView: nukeRequest.thumbnail != nil)
        }
        completionBox.value(response.image, animation, response.cacheType == .memory, nil)
      } catch {
        progressTask?.cancel()
        guard !Task.isCancelled else { return }
        completionBox.value(nil, nil, false, Self.classify(error))
      }
    }
    return NukeLoadTask(imageTask: imageTask, task: task, progressTask: progressTask)
  }

  // MARK: - Display

  /// NukeUI's `AnimatedImageView`: shares frames across views and respects
  /// visibility and Reduce Motion.
  @MainActor
  public func makeImageView() -> UIImageView {
    let imageView = AnimatedImageView()
    // Loop forever like Android, whatever the file says.
    imageView.playerOptions.loopCount = .infinite
    return imageView
  }

  @MainActor
  public func display(_ image: UIImage, animation: Any?, in imageView: UIImageView) {
    // The still first (also stops any playing animation).
    imageView.image = image
    guard let animation = animation as? PlayableAnimation,
      let imageView = imageView as? AnimatedImageView
    else { return }
    // Downsample frames only if the still was.
    imageView.isAutomaticDownsamplingEnabled = animation.fitsView
    imageView.animation = animation.source
  }

  // MARK: - Cache management (TurboImageModule)

  @objc(imageSizeForRequest:completion:)
  public func imageSize(
    for request: TIImageRequest,
    completion: @escaping (CGSize, (any Error)?) -> Void
  ) -> any TIImageLoadTask {
    let nukeRequest = Self.makeNukeRequest(from: request)
    let pipeline = pipeline(for: request)
    let completionBox = UncheckedSendable(completion)
    let task = Task { @MainActor in
      do {
        // Bytes through the same caches as a load.
        let (data, _) = try await pipeline.data(for: nukeRequest)
        let size: CGSize
        if let header = Self.headerPixelSize(of: data) {
          size = header
        } else {
          // SVG: decode; a vector reports its canvas at screen scale, as on Android.
          let image = try await pipeline.image(for: nukeRequest)
          let scale = image.cgImage == nil ? UITraitCollection.current.displayScale : image.scale
          size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        }
        guard !Task.isCancelled else { return }
        completionBox.value(size, nil)
      } catch {
        guard !Task.isCancelled else { return }
        completionBox.value(.zero, Self.classify(error))
      }
    }
    return AsyncTask(task: task)
  }

  /// First frame's oriented pixel size from the header, or nil.
  static func headerPixelSize(of data: Data) -> CGSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { return nil }
    // Orientations 5-8 swap the axes.
    let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
    return orientation >= 5
      ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
  }

  public func prefetchRequest(
    _ request: TIImageRequest,
    completion: @escaping (Bool) -> Void
  ) -> any TIImageLoadTask {
    var nukeRequest = Self.makeNukeRequest(from: request)
    // Prefetches yield to on-screen loads.
    nukeRequest.priority = .low
    let completionBox = UncheckedSendable(completion)
    // Disk-only prefetch: fetch bytes, decode nothing.
    guard request.memoryCacheWrite else {
      let pipeline = pipeline(for: request)
      let task = Task { @MainActor in
        let succeeded = (try? await pipeline.data(for: nukeRequest)) != nil
        guard !Task.isCancelled else { return }
        completionBox.value(succeeded)
      }
      return AsyncTask(task: task)
    }
    let imageTask = pipeline(for: request).imageTask(with: nukeRequest)
    let task = Task { @MainActor in
      let succeeded = (try? await imageTask.response) != nil
      guard !Task.isCancelled else { return }
      completionBox.value(succeeded)
    }
    return NukeLoadTask(imageTask: imageTask, task: task, progressTask: nil)
  }

  private func remember(_ variant: Variant, of cacheKey: String) {
    variantsLock.withLock { rememberLocked(variant, of: cacheKey) }
  }

  private func rememberLocked(_ variant: Variant, of cacheKey: String) {
    if variants[cacheKey, default: []].insert(variant).inserted {
      variantCount += 1
    }
    guard variantCount > sweepThreshold else { return }
    let cache = pipeline.cache
    for (key, seen) in variants {
      let live = seen.filter {
        cache.containsCachedImage(for: Self.request(for: $0, of: key), caches: .memory)
      }
      variants[key] = live.isEmpty ? nil : live
    }
    variantCount = variants.values.reduce(0) { $0 + $1.count }
    sweepThreshold = max(minimumSweepThreshold, 2 * variantCount)
  }

  public func removeCachedImage(for request: TIImageRequest) {
    let cacheKey = request.cacheKey
    let original = Self.keyOnlyRequest(cacheKey)
    // The original's image entries, then its bytes on disk.
    pipeline.cache.removeCachedImage(for: original, caches: .all)
    pipeline.cache.removeCachedData(for: original)
    // Variants are memory-only; the memory cache is shared by both pipelines.
    let seen =
      variantsLock.withLock {
        let removed = variants.removeValue(forKey: cacheKey) ?? []
        variantCount -= removed.count
        return removed
      }
    for variant in seen {
      pipeline.cache.removeCachedImage(for: Self.request(for: variant, of: cacheKey), caches: .memory)
    }
    // Keyed by URL alone; headers never key caches.
    urlCache.removeCachedResponse(for: URLRequest(url: request.url))
  }

  public func clearMemoryCache() {
    pipeline.cache.removeAll(caches: .memory)
    variantsLock.withLock {
      variants.removeAll()
      variantCount = 0
    }
  }

  public func clearDiskCache() {
    pipeline.cache.removeAll(caches: .disk)
    urlCache.removeAllCachedResponses()
  }

  public func memoryCachedImage(forKey cacheKey: String) -> UIImage? {
    let cache = pipeline.cache
    if let image = cache.cachedImage(for: Self.keyOnlyRequest(cacheKey), caches: .memory)?.image {
      return image
    }
    // Any unprocessed size will do for a placeholder; processed ones won't.
    let unprocessed = variantsLock.withLock {
      variants[cacheKey]?.filter { $0.processorID.isEmpty } ?? []
    }
    for variant in unprocessed {
      let request = Self.request(for: variant, of: cacheKey)
      if let image = cache.cachedImage(for: request, caches: .memory)?.image {
        return image
      }
    }
    return nil
  }

  /// Addresses `variant`'s memory entry; Nuke matches processors by id only.
  private static func request(for variant: Variant, of cacheKey: String) -> ImageRequest {
    var request = keyOnlyRequest(cacheKey)
    request.thumbnail = variant.thumbnail
    if !variant.processorID.isEmpty {
      request.processors = [ImageProcessors.Anonymous(id: variant.processorID) { $0 }]
    }
    return request
  }

  /// Parsed once; sweeps build many requests.
  private static let keyOnlyURL = URL(string: "turboimage://cache-key")

  /// Nuke keys caches by `imageID`, so this addresses a load's entries. The
  /// URL is never fetched.
  private static func keyOnlyRequest(_ cacheKey: String) -> ImageRequest {
    var request = ImageRequest(url: keyOnlyURL)
    request.imageID = cacheKey
    return request
  }

  /// Nuke errors to `LoadErrorCode`. Keep in step with Android's `classify`.
  /// Internal, not private, so the adapter tests can map Nuke's errors.
  static func classify(_ error: any Error) -> NSError {
    // Narrowed here: do/catch doesn't infer typed throws yet.
    guard let error = error as? ImagePipeline.Error else {
      return NSError(
        domain: TIImageLoadErrorDomain,
        code: TIImageLoadError.Code.unknown.rawValue,
        userInfo: [NSLocalizedDescriptionKey: String(describing: error)]
      )
    }
    let code: TIImageLoadError.Code
    switch error {
    case .dataMissingInCache:
      code = .notCached
    case .dataLoadingFailed, .dataIsEmpty, .dataDownloadExceededMaximumSize:
      code = .network
    case .decoderNotRegistered, .decodingFailed, .processingFailed:
      code = .decode
    case .imageRequestMissing, .pipelineInvalidated, .cancelled:
      code = .unknown
    @unknown default:
      code = .unknown
    }
    return NSError(
      domain: TIImageLoadErrorDomain,
      code: code.rawValue,
      // Nuke's `description` is readable; the bridged NSError text isn't.
      userInfo: [NSLocalizedDescriptionKey: error.description]
    )
  }

  /// Maps a resolved request to Nuke; the core made every policy decision.
  private static func makeNukeRequest(from request: TIImageRequest) -> ImageRequest {
    var options: ImageRequest.Options = []
    if !request.memoryCacheRead { options.insert(.disableMemoryCacheReads) }
    if !request.memoryCacheWrite { options.insert(.disableMemoryCacheWrites) }
    if !request.diskCacheRead { options.insert(.disableDiskCacheReads) }
    if !request.diskCacheWrite { options.insert(.disableDiskCacheWrites) }
    if !request.allowNetwork { options.insert(.returnCacheDataDontLoad) }

    // Headers never key caches; `imageID` does.
    var urlRequest = URLRequest(url: request.url)
    for pair in request.headers where pair.count == 2 {
      urlRequest.addValue(pair[1], forHTTPHeaderField: pair[0])
    }
    // On `httpPipeline` the default policy honours `Cache-Control`. URLSession
    // can't skip storing per request; the core never asks for that.
    if request.httpCache && !request.diskCacheRead {
      urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
    }
    var nukeRequest = ImageRequest(urlRequest: urlRequest, options: options)
    // `imageID` keys both Nuke's memory and data caches.
    nukeRequest.imageID = request.cacheKey
    nukeRequest.thumbnail = thumbnail(for: request)
    // One opaque step. Its id keys memory; disk keeps the original (like
    // Coil). A nil result fails as `decode`.
    if let processor = request.processor, !request.processorKey.isEmpty {
      let processorBox = UncheckedSendable(processor)
      // Rasterise vectors at the vector target first, or they'd be drawn at 1x.
      nukeRequest.processors = [
        CoreProcessor(
          identifier: processorID(for: request), processor: processorBox,
          vectorTarget: VectorTarget(
            size: request.vectorDecodeSize, fill: request.vectorDecodeFill,
            displayScale: request.displayScale))
      ]
    }
    return nukeRequest
  }

  /// The decode bound as Nuke thumbnail options (ImageIO, no full bitmap).
  /// Keys memory per size; disk keeps the original.
  private static func thumbnail(for request: TIImageRequest) -> ImageRequest.ThumbnailOptions? {
    let size = request.decodeSize
    guard size.width > 0 else { return nil }
    guard size.height > 0 else {
      // Width only: a box too tall to bind.
      return .init(
        size: CGSize(width: size.width, height: unboundedPixels), unit: .pixels,
        contentMode: .aspectFit)
    }
    return .init(size: size, unit: .pixels, contentMode: request.decodeFill ? .aspectFill : .aspectFit)
  }

  /// Taller than any image; exact as a `Float`.
  private static let unboundedPixels = CGFloat(1 << 30)

  /// Processor id for the memory key: the core's key plus the vector draw
  /// size when it differs from the decode bound, so different-size views of
  /// a processed SVG don't share an entry. Vector-ness is unknown before
  /// decode, so bitmaps get duplicate entries in that rare case.
  /// TODO: share those (remember vector-ness per key, or own a memory cache).
  private static func processorID(for request: TIImageRequest) -> String {
    let base = "com.turboimage.\(request.processorKey)"
    let vector = request.vectorDecodeSize
    let sameAsDecodeBound =
      vector == request.decodeSize && request.vectorDecodeFill == request.decodeFill
    // Zero means the image's own size.
    guard vector.width > 0, !sameAsDecodeBound else { return base }
    // Same rounding as `VectorTarget.draw`.
    let size = "\(Int(vector.width.rounded()))x\(Int(vector.height.rounded()))"
    return "\(base)@vector=\(size)\(request.vectorDecodeFill ? ",fill" : "")"
  }
}

/// The seam's processor for Nuke. Needs the container to detect vectors.
private struct CoreProcessor: ImageProcessing {
  /// `processorID(for:)`; the memory entry is addressed by it alone.
  let identifier: String
  let processor: UncheckedSendable<TIImageProcessor>
  let vectorTarget: VectorTarget

  func process(_ image: PlatformImage) -> PlatformImage? {
    processor.value(image)
  }

  func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
    var image = container.image
    if container.type == SVGDecoder.assetType {
      // No area: leave it to the processor to fail.
      image = vectorTarget.draw(image) ?? image
    }
    guard let processed = process(image) else {
      throw ImageProcessingError.unknown
    }
    var result = container
    result.image = processed
    // Processed animations become stills (ADR 0007).
    result.animation = nil
    result.data = nil
    return result
  }
}

/// The opaque `animation`: a source and how to size its frames.
private final class PlayableAnimation: NSObject, Sendable {
  let source: AnimatedImageSource
  /// Whether the still was decoded for the view.
  let fitsView: Bool

  init(source: AnimatedImageSource, fitsView: Bool) {
    self.source = source
    self.fitsView = fitsView
  }
}

/// For values made safe by contract rather than by the type system.
private struct UncheckedSendable<Value>: @unchecked Sendable {
  let value: Value
  init(_ value: Value) { self.value = value }
}
