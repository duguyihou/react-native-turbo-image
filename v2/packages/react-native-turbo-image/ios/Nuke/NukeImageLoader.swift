// Nuke adapter for TurboImage (iOS).
//
// Everything Nuke-specific lives in this target. The rest of TurboImage
// talks to it only through `TIImageLoading` (ios/LoaderAPI), so Nuke can be
// upgraded (13 → 14) or replaced without touching the Fabric layer or the
// JS API (RFC rule 1). Nothing here is `public` except the ObjC entry point
// the registry looks up by name.

import Foundation
import Nuke
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

@objc(TurboImageNukeLoader)
public final class NukeImageLoader: NSObject, TIImageLoading, @unchecked Sendable {
  // `ImagePipeline` is Sendable; this is the only stored state.
  private let pipeline: ImagePipeline

  /// Disk tier size. Must equal `DISK_CACHE_BYTES` in the Android adapter.
  static let diskCacheBytes = 150 * 1024 * 1024

  @objc public override init() {
    // Explicit configuration rather than `ImagePipeline.shared`, so the host
    // app's own use of Nuke cannot change TurboImage's cache behaviour (and
    // vice versa). Cross-platform cache contract (RFC rule 3, mirrored in
    // CoilImageLoaderAdapter.kt):
    //   * disk tier = TurboImage-owned data cache that stores original bytes,
    //   * HTTP caching disabled (`withDataCache` sets `urlCache = nil`), so
    //     `Cache-Control` headers do not affect hits on either platform,
    //   * concurrent requests for the same key are coalesced (Nuke default).
    var configuration = ImagePipeline.Configuration.withDataCache(
      name: "com.turboimage.DataCache",
      sizeLimit: Self.diskCacheBytes
    )
    // `withDataCache` reuses `ImageCache.shared`; give TurboImage its own
    // memory tier so the host app cannot evict or poison it.
    configuration.imageCache = ImageCache()
    configuration.isTaskCoalescingEnabled = true
    pipeline = ImagePipeline(configuration: configuration)
    super.init()
  }

  public func loadImage(
    with request: TIImageRequest,
    progress: TIImageLoadProgress?,
    completion: @escaping TIImageLoadCompletion
  ) -> any TIImageLoadTask {
    let imageTask = pipeline.imageTask(with: Self.makeNukeRequest(from: request))

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
        let image = try await imageTask.image
        progressTask?.cancel()
        // Dropping results after cancellation is part of the
        // request-lifecycle contract: a recycled view must never receive
        // the image for its previous source.
        guard !Task.isCancelled else { return }
        completionBox.value(image, nil)
      } catch {
        progressTask?.cancel()
        guard !Task.isCancelled else { return }
        completionBox.value(nil, Self.classify(error))
      }
    }
    return NukeLoadTask(imageTask: imageTask, task: task, progressTask: progressTask)
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

    var nukeRequest = ImageRequest(url: request.url, options: options)
    // `imageID` keys both Nuke's memory and data caches.
    nukeRequest.imageID = request.cacheKey
    return nukeRequest
  }
}

/// Minimal escape hatch for values whose thread-safety is guaranteed by a
/// documented contract rather than by the type system.
private struct UncheckedSendable<Value>: @unchecked Sendable {
  let value: Value
  init(_ value: Value) { self.value = value }
}
