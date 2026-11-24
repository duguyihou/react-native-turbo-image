// Nuke adapter for TurboImage (iOS).
//
// Everything Nuke-specific lives in this target. The rest of TurboImage
// talks to it only through `TIImageLoading` (ios/LoaderAPI), so Nuke can be
// upgraded (13 → 14) or replaced without touching the Fabric layer or the
// JS API (RFC rule 1). Nothing here is `public` except the ObjC entry point
// the registry looks up by name.

import Foundation
import ImageIO
import Nuke
import NukeUI
import UIKit

// Under SwiftPM the seam is a separate Clang target and must be imported.
// Under CocoaPods it is compiled into the same module, so it is already
// visible and there is nothing to import.
#if canImport(TurboImageLoaderAPI)
  import TurboImageLoaderAPI
#endif

/// Wraps a Nuke `ImageTask` so the Fabric layer can cancel it without
/// seeing Nuke types.
private final class NukeLoadTask: NSObject, TIImageLoadTask, @unchecked Sendable {
  // Written once on the main thread before the task is returned, then only
  // read. `@unchecked Sendable` is sound because of that publish-once rule.
  private let task: Task<Void, Never>
  private let progressTask: Task<Void, Never>?
  private let imageTask: ImageTask

  init(imageTask: ImageTask, task: Task<Void, Never>, progressTask: Task<Void, Never>?) {
    self.imageTask = imageTask
    self.task = task
    self.progressTask = progressTask
  }

  func cancel() {
    // All idempotent: Nuke ignores repeated cancels, and cancelling the Swift
    // Tasks makes the awaiting closures drop their results.
    imageTask.cancel()
    task.cancel()
    progressTask?.cancel()
  }
}

/// The handle of `imageSize` and of a disk-only prefetch: cancelling the
/// Swift Task cancels the awaited Nuke work and drops the result.
private final class AsyncTask: NSObject, TIImageLoadTask, @unchecked Sendable {
  private let task: Task<Void, Never>
  init(task: Task<Void, Never>) { self.task = task }
  func cancel() { task.cancel() }
}

@objc(TurboImageNukeLoader)
public final class NukeImageLoader: NSObject, TIImageLoading, @unchecked Sendable {
  // `ImagePipeline` is Sendable.
  /// Every policy but `urlCache`: disk tier = `DataCache`, keyed by `cacheKey`.
  /// Internal, not private, only so tests can evict from the memory cache
  /// without going through this adapter.
  let pipeline: ImagePipeline
  /// `urlCache` requests (`TIImageRequest.httpCache`): disk tier = `urlCache`.
  private let httpPipeline: ImagePipeline
  /// The HTTP cache behind `httpPipeline`. Kept to evict from and clear it.
  /// Internal, not private, only so tests can read its capacity.
  let urlCache: URLCache

  /// One memory entry of a cache key other than the plain original. Nuke's
  /// memory key is (imageID, thumbnail, processors), so each processed
  /// variant and each decode size is its own entry.
  private struct Variant: Hashable {
    /// The identifier of the request's Nuke processor (`processorID`), which
    /// is what Nuke puts in the memory key. Empty: not processed.
    let processorID: String
    let thumbnail: ImageRequest.ThumbnailOptions?
  }

  // Variants seen per cache key, so `removeCachedImage` can evict them all
  // and the `memoryCacheKey` placeholder can find a downscaled image: Nuke's
  // memory cache cannot be enumerated. Coil can match on the key string
  // instead, so Android needs no such index. Written from `load` (main) and
  // read from the cache module (any thread), hence the lock.
  //
  // Bounded by sweeping: once it holds more than `sweepThreshold` variants,
  // those whose memory entry Nuke has evicted are dropped (see
  // `rememberLocked`). A dropped variant needs no eviction and cannot serve
  // a placeholder, so nothing that reads the index notices.
  private let variantsLock = NSLock()
  private var variants: [String: Set<Variant>] = [:]
  /// How many variants `variants` holds, across keys. Read by tests.
  private(set) var variantCount = 0
  /// Sweep once `variantCount` passes this. Reset to twice what survives a
  /// sweep, so the sweeps' cost (one memory-cache lookup per variant) is
  /// amortized O(1) per load, and the index stays within about twice the
  /// variants still in memory, or this floor.
  private var sweepThreshold: Int
  private let minimumSweepThreshold: Int

  /// Disk tier size. Must equal `DISK_CACHE_BYTES` in the Android adapter (CoilLoaderSetup.kt).
  static let diskCacheBytes = 150 * 1024 * 1024

  @objc public override convenience init() {
    self.init(minimumSweepThreshold: 512)
  }

  /// `minimumSweepThreshold`: the variants the index holds before its first
  /// sweep. Lowered by tests only, to reach a sweep in a few loads.
  init(minimumSweepThreshold: Int) {
    self.minimumSweepThreshold = minimumSweepThreshold
    sweepThreshold = minimumSweepThreshold
    // Explicit configuration rather than `ImagePipeline.shared`, so the host
    // app's own use of Nuke cannot change TurboImage's cache behaviour (and
    // vice versa). Cross-platform cache contract (RFC rule 3, mirrored in
    // CoilImageLoaderAdapter.kt):
    //   * disk tier = TurboImage-owned data cache that stores original bytes,
    //   * HTTP caching disabled (`withDataCache` sets `urlCache = nil`), so
    //     `Cache-Control` headers do not affect hits on either platform,
    //   * concurrent requests for the same key are coalesced (Nuke default).
    // Not `ImageCache.shared`: TurboImage gets its own memory tier, so the
    // host app cannot evict or poison it. Both pipelines share it, because
    // the memory tier is one cache whatever the disk policy (core rule).
    // `TurboImage.configureCache`, read once: the caches are built here.
    let maxMemoryCost = TIImageLoaderRegistry.cacheMaxMemoryCost
    let diskBytes =
      TIImageLoaderRegistry.cacheMaxDiskSize > 0
      ? TIImageLoaderRegistry.cacheMaxDiskSize : Self.diskCacheBytes
    let imageCache =
      maxMemoryCost > 0 ? ImageCache(costLimit: maxMemoryCost) : ImageCache()
    // One for both pipelines too: a key names one image whatever the policy.
    let animations = AnimationSources()
    pipeline = Self.makePipeline(
      .withDataCache(name: "com.turboimage.DataCache", sizeLimit: diskBytes),
      imageCache: imageCache, animations: animations)

    // `cachePolicy="urlCache"`: a second pipeline whose only disk tier is an
    // HTTP cache. URLSession then does what the policy promises: it serves
    // an entry while `Cache-Control`/`Expires` say it is fresh, revalidates
    // a stale one (`If-None-Match`, a 304 costs no body), and never stores
    // `no-store`. Coil's `CacheControlCacheStrategy` does the same on Android.
    //
    // A pipeline of its own because Nuke's `DataCache` sits in front of the
    // loader and has no notion of freshness: sharing one would serve expired
    // images. And a `URLCache` of its own, rather than `URLCache.shared` or
    // Nuke's, so the host app's networking cannot fill or clear it.
    //
    // No memory capacity: decoded images are in `imageCache` already.
    // URLCache does not store a response larger than 5% of its disk capacity
    // (7.5 MB here); such an image is refetched every time.
    let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    urlCache = URLCache(
      memoryCapacity: 0,
      // Not `configureCache`'s size: that one sizes the store the other
      // policies use (`DataCache`), the cache apps mean. This one keeps its
      // 150 MB, and with it the largest response it stores (5%).
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

  /// What both pipelines have in common; they differ only in their disk tier.
  private static func makePipeline(
    _ base: ImagePipeline.Configuration, imageCache: ImageCache, animations: AnimationSources
  ) -> ImagePipeline {
    var configuration = base
    configuration.imageCache = imageCache
    configuration.isTaskCoalescingEnabled = true
    // Animated GIF/APNG/WebP and SVG, chosen by content (NukeDecoders.swift).
    configuration.makeImageDecoder = { TurboImageDecoders.make($0, animations: animations) }
    // Off because `ContentDecoder` attaches the animations itself: Nuke's
    // own parsing skips every downscaled request and covers formats
    // TurboImage shows as stills (NukeDecoders.swift, `AnimationSources`).
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
    // Read back from the Nuke request, so the index holds exactly what Nuke
    // keys the entry by.
    let processorID = nukeRequest.processors.first?.identifier ?? ""
    let variant =
      !processorID.isEmpty || nukeRequest.thumbnail != nil
      ? Variant(processorID: processorID, thumbnail: nukeRequest.thumbnail) : nil
    let cacheKey = request.cacheKey
    if let variant {
      // Before the load, so a `dispose` that runs while it does still finds
      // the entry the load is about to write.
      remember(variant, of: cacheKey)
    }
    let imageTask = pipeline(for: request).imageTask(with: nukeRequest)

    // Progress runs in its own MainActor task. The completion path cancels
    // it *before* calling completion; because both run on the main actor,
    // the `isCancelled` check below guarantees no progress callback lands
    // after completion (seam contract).
    let progressTask: Task<Void, Never>? = progress.map { callback in
      let progressBox = UncheckedSendable(callback)
      return Task { @MainActor in
        for await update in imageTask.progress {
          if Task.isCancelled { break }
          progressBox.value(update.completed, update.total)
        }
      }
    }

    // Hop the ObjC block into a Sendable box: TIImageLoadCompletion is an
    // ObjC block type the compiler cannot prove Sendable. The completion
    // contract says it is only invoked on the main thread, which the
    // `@MainActor` hop below guarantees.
    let completionBox = UncheckedSendable(completion)
    let task = Task { @MainActor in
      do {
        let response = try await imageTask.response
        progressTask?.cancel()
        // Dropping results after cancellation is part of the
        // request-lifecycle contract: a recycled view must never receive
        // the image for its previous source.
        // Again now that Nuke has stored the image: a sweep that ran during
        // the load found no entry yet and dropped the variant.
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

  /// NukeUI's image view: a UIImageView that also plays an animation, from
  /// frames it decodes as it shows them and shares with every other view of
  /// the same animation (`AnimatedImageFramePool`). It pauses while it is
  /// outside a window, hidden or transparent, and shows a still while Reduce
  /// Motion is on or Auto-Play Animated Images is off.
  @MainActor
  public func makeImageView() -> UIImageView {
    let imageView = AnimatedImageView()
    // Every animation loops for as long as it is shown, whatever count the
    // file declares: what Coil's animated drawables do on Android, and what
    // `UIImage.animatedImage` did here before. Nuke's default follows the
    // file, as browsers do, and would play a GIF without a loop count once.
    imageView.playerOptions.loopCount = .infinite
    return imageView
  }

  @MainActor
  public func display(_ image: UIImage, animation: Any?, in imageView: UIImageView) {
    // The still first: it is what shows until the first frame is decoded,
    // and all that shows in a view that cannot play. Setting `image` also
    // stops the animation the view was playing.
    imageView.image = image
    guard let animation = animation as? PlayableAnimation,
      let imageView = imageView as? AnimatedImageView
    else { return }
    // Frames are decoded no larger than the view draws them, unless the
    // request asked for the image at its own size (`allowDownscaling` off,
    // for a view that is zoomed): the same rule the still was decoded by.
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
        // The bytes, through the same caches as a load: a hit reads the disk,
        // a miss downloads and stores the original.
        let (data, _) = try await pipeline.data(for: nukeRequest)
        let size: CGSize
        if let header = Self.headerPixelSize(of: data) {
          size = header
        } else {
          // Not a format ImageIO bounds (SVG): decode with the adapter's own
          // decoders. A vector has no pixels; it reports its canvas at the
          // screen's scale, the size it draws at, as Android does.
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

  /// The first frame's size in pixels from the header, turned by the EXIF
  /// orientation as a decode would; nil if ImageIO cannot read one.
  static func headerPixelSize(of data: Data) -> CGSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0
    else { return nil }
    // Orientations 5-8 swap the axes (transposed, rotated a quarter turn).
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
    // Nothing will keep a decoded image (`destination: 'disk'`): fetch the
    // bytes through the same caches as a load, as `imageSize` does, and
    // decode nothing.
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
    // Decoded image (memory) and processed variants (disk), then the
    // original bytes, which DataCache stores under the data key.
    pipeline.cache.removeCachedImage(for: original, caches: .all)
    pipeline.cache.removeCachedData(for: original)
    // Variants live in memory only (originals-only disk policy). The memory
    // cache is shared, so one pipeline's view of it reaches every entry.
    let seen =
      variantsLock.withLock {
        let removed = variants.removeValue(forKey: cacheKey) ?? []
        variantCount -= removed.count
        return removed
      }
    for variant in seen {
      pipeline.cache.removeCachedImage(for: Self.request(for: variant, of: cacheKey), caches: .memory)
    }
    // The HTTP cache is keyed by URL. Headers are not part of that identity
    // here (core rule), so a bare request addresses the entry.
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
    // A view usually stores the image downscaled to its own size, under a
    // key that includes that size. Any unprocessed size will do for a
    // placeholder; a blurred or tinted variant must not stand in.
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

  /// A request that addresses `variant`'s memory entry. Nuke compares
  /// processors by identifier, so a closure-less stand-in with the same id
  /// addresses the entry the real processor wrote.
  private static func request(for variant: Variant, of cacheKey: String) -> ImageRequest {
    var request = keyOnlyRequest(cacheKey)
    request.thumbnail = variant.thumbnail
    if !variant.processorID.isEmpty {
      request.processors = [ImageProcessors.Anonymous(id: variant.processorID) { $0 }]
    }
    return request
  }

  /// Nuke derives both cache keys from `imageID` when it is set, so a request
  /// carrying only the key addresses the same entries a view load wrote. The
  /// URL is never fetched; it only has to be non-nil.
  private static func keyOnlyRequest(_ cacheKey: String) -> ImageRequest {
    var request = ImageRequest(url: URL(string: "turboimage://cache-key"))
    request.imageID = cacheKey
    return request
  }

  /// Maps Nuke's errors onto TurboImage's cross-platform codes
  /// (`turboimage::LoadErrorCode`). Must stay in step with
  /// `CoilImageLoaderAdapter.classify` on Android.
  private static func classify(_ error: any Error) -> NSError {
    // `imageTask.image` throws `ImagePipeline.Error`, but do/catch only
    // infers typed errors with the FullTypedThrows upcoming feature, so the
    // caught value arrives as `any Error` and is narrowed here.
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
      // Nuke's `description` is readable ("Data is missing in cache")
      // unlike the bridged NSError text ("…Nuke.ImagePipeline.Error error 4").
      userInfo: [NSLocalizedDescriptionKey: error.description]
    )
  }

  /// Mechanical translation of a resolved TurboImage request. No policy
  /// decisions are made here; they were made by the C++ core.
  private static func makeNukeRequest(from request: TIImageRequest) -> ImageRequest {
    var options: ImageRequest.Options = []
    if !request.memoryCacheRead { options.insert(.disableMemoryCacheReads) }
    if !request.memoryCacheWrite { options.insert(.disableMemoryCacheWrites) }
    if !request.diskCacheRead { options.insert(.disableDiskCacheReads) }
    if !request.diskCacheWrite { options.insert(.disableDiskCacheWrites) }
    if !request.allowNetwork { options.insert(.returnCacheDataDontLoad) }

    // Headers need a URLRequest; they are not part of Nuke's cache keys,
    // which come from `imageID` below (core rule: headers never key caches).
    var urlRequest = URLRequest(url: request.url)
    for pair in request.headers where pair.count == 2 {
      urlRequest.addValue(pair[1], forHTTPHeaderField: pair[0])
    }
    // HTTP-cache requests run on `httpPipeline`, where the disk tier is the
    // session's URLCache and the Nuke disk options above address nothing.
    // The protocol policy (the default) is what honours `Cache-Control`.
    // URLSession has no per-request "do not store", so a write-only or
    // read-only HTTP tier cannot be expressed; the core never asks for one.
    if request.httpCache && !request.diskCacheRead {
      urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
    }
    var nukeRequest = ImageRequest(urlRequest: urlRequest, options: options)
    // `imageID` keys both Nuke's memory and data caches.
    nukeRequest.imageID = request.cacheKey
    nukeRequest.thumbnail = thumbnail(for: request)
    // One opaque step; the core owns the algorithms. Nuke folds its id into
    // the memory key (one entry per variant) and, with the default
    // `.storeOriginalData` policy, keeps only the original on disk, which is
    // also what Coil does. A nil result fails the load as `processingFailed`,
    // classified as `decode`.
    if let processor = request.processor, !request.processorKey.isEmpty {
      let processorBox = UncheckedSendable(processor)
      // The core works on pixels, and a vector image has none until it is
      // drawn. Left to the seam's processor it would be drawn at its own
      // size at 1x (measured: 120×80 px for a 720×480 px view, then
      // stretched), so it is drawn at the request's vector target first.
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

  /// The seam's decode bound as Nuke thumbnail options: ImageIO decodes
  /// straight to the smaller size, without allocating the full bitmap, and
  /// never upscales. Nuke adds the options to the memory key (one entry per
  /// size) and still stores, and reads, the original bytes on disk.
  private static func thumbnail(for request: TIImageRequest) -> ImageRequest.ThumbnailOptions? {
    let size = request.decodeSize
    guard size.width > 0 else { return nil }
    guard size.height > 0 else {
      // Width only. Nuke takes a box; one this tall never binds, so fitting
      // inside it is fitting the width.
      return .init(
        size: CGSize(width: size.width, height: unboundedPixels), unit: .pixels,
        contentMode: .aspectFit)
    }
    return .init(size: size, unit: .pixels, contentMode: request.decodeFill ? .aspectFill : .aspectFit)
  }

  /// Taller than any image, and exactly representable as the `Float` Nuke
  /// stores sizes in.
  private static let unboundedPixels = CGFloat(1 << 30)

  /// The identifier Nuke adds to the memory key of a processed image:
  /// everything that decides the processed pixels and is not in the key
  /// already.
  ///
  /// That is the core's processor key and, when it is not the decode bound,
  /// the size a vector is drawn at. The decode bound is in the key as the
  /// request's `thumbnail`. With `allowDownscaling` off there is no bound,
  /// but a processed SVG is still drawn for the view (`vectorDecodeSize`),
  /// and without the size here two views of different sizes shared one
  /// entry: the second was handed the first one's bitmap.
  ///
  /// Whether the source is a vector is only known once it is decoded, after
  /// the key is needed, so a bitmap pays for this too: processed with
  /// `allowDownscaling` off and shown at two sizes, it is kept once per
  /// size, although the entries are identical.
  /// TODO: share those. It needs the vector-ness of a cache key remembered
  /// from its first decode, or a memory cache of our own in front of Nuke's.
  ///
  /// Tried and rejected: letting a vector pass through Nuke's processor
  /// untouched and drawing and processing it in `loadImage`, with the
  /// result stored under a key of the adapter's own. It spares bitmaps,
  /// but it moves processing, cache writes, coalescing and cancellation
  /// for SVGs out of Nuke's pipeline into code this adapter has to
  /// maintain, to save memory in a case that needs a processor,
  /// `allowDownscaling` off and one bitmap at two sizes all at once.
  private static func processorID(for request: TIImageRequest) -> String {
    let base = "com.turboimage.\(request.processorKey)"
    let vector = request.vectorDecodeSize
    let sameAsDecodeBound =
      vector == request.decodeSize && request.vectorDecodeFill == request.decodeFill
    // A zero size is the image's own size: nothing of the view's is in it.
    guard vector.width > 0, !sameAsDecodeBound else { return base }
    // Whole pixels: the same rounding as `VectorTarget.draw`'s result.
    let size = "\(Int(vector.width.rounded()))x\(Int(vector.height.rounded()))"
    return "\(base)@vector=\(size)\(request.vectorDecodeFill ? ",fill" : "")"
  }
}

/// The seam's processor as a Nuke processor. Not `ImageProcessors.Anonymous`
/// because that sees only the image, and whether an image is a vector is
/// known from its container's type.
private struct CoreProcessor: ImageProcessing {
  /// `processorID(for:)` of the request. `request(for:of:)` addresses the
  /// processed memory entry by this identifier alone.
  let identifier: String
  let processor: UncheckedSendable<TIImageProcessor>
  let vectorTarget: VectorTarget

  func process(_ image: PlatformImage) -> PlatformImage? {
    processor.value(image)
  }

  func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
    var image = container.image
    if container.type == SVGDecoder.assetType {
      // A vector that cannot be drawn (no area) is left to the processor,
      // which fails the load the same way it always did.
      image = vectorTarget.draw(image) ?? image
    }
    guard let processed = process(image) else {
      throw ImageProcessingError.unknown
    }
    var result = container
    result.image = processed
    // Processors apply to the still: a processed animation is its first
    // frame (ADR 0007). Kept, the animation would play the unprocessed
    // frames over it. Nuke drops both for its own processors as well.
    result.animation = nil
    result.data = nil
    return result
  }
}

/// What the completion hands the view as `animation`, and `display` gets
/// back: an animation and how its frames are to be sized.
private final class PlayableAnimation: NSObject, Sendable {
  let source: AnimatedImageSource
  /// Whether the request was decoded for its view (`TIImageRequest.decodeSize`).
  let fitsView: Bool

  init(source: AnimatedImageSource, fitsView: Bool) {
    self.source = source
    self.fitsView = fitsView
  }
}

/// Minimal escape hatch for values whose thread-safety is guaranteed by a
/// documented contract rather than by the type system.
private struct UncheckedSendable<Value>: @unchecked Sendable {
  let value: Value
  init(_ value: Value) { self.value = value }
}
