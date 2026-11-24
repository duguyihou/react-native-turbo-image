// Adapter loads: decode size and seam error codes. The core is not involved,
// so a failure here points at the adapter.

import Testing
import TurboImageLoaderAPI
import UIKit

@testable import TurboImageNuke

@MainActor
@Suite(.serialized)
struct LoadingTests {
  let adapter = Adapter()

  // MARK: Decode size (`TIImageRequest.decodeSize`)

  @Test func withoutABoundTheImageKeepsItsSize() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.png(), decodeSize: .zero))

    #expect(loaded.pixelSize == Fixture.size)
    #expect(loaded.error == nil)
  }

  @Test func aBoundTheImageFitsInsideShrinksIt() async throws {
    // 40×30 inside 20×20: the width binds.
    let loaded = await adapter.load(
      adapter.request(for: try Fixture.png(), decodeSize: CGSize(width: 20, height: 20)))

    #expect(loaded.pixelSize == CGSize(width: 20, height: 15))
  }

  @Test func aBoundTheImageMustCoverShrinksItLess() async throws {
    // 40×30 covering 20×20: the height binds, and the width overhangs.
    let loaded = await adapter.load(
      adapter.request(
        for: try Fixture.png(), decodeSize: CGSize(width: 20, height: 20), decodeFill: true))

    let size = try #require(loaded.pixelSize)
    #expect(size.height >= 20 && size.width >= 20)
    #expect(size.width < Fixture.size.width)
  }

  /// A zero height bounds the width alone (`resize` with a width only).
  @Test func aWidthOnlyBoundKeepsTheAspectRatio() async throws {
    let loaded = await adapter.load(
      adapter.request(for: try Fixture.png(), decodeSize: CGSize(width: 20, height: 0)))

    #expect(loaded.pixelSize == CGSize(width: 20, height: 15))
  }

  @Test func decodingNeverUpscales() async throws {
    let loaded = await adapter.load(
      adapter.request(for: try Fixture.png(), decodeSize: CGSize(width: 400, height: 300)))

    #expect(loaded.pixelSize == Fixture.size)
  }

  // MARK: Failures (`TIImageLoadErrorCode`)

  @Test func aSourceThatCannotBeFetchedIsANetworkError() async {
    let loaded = await adapter.load(adapter.request(for: Fixture.missing()))

    #expect(loaded.image == nil)
    #expect(loaded.errorCode == .network)
  }

  @Test func bytesNoDecoderRecognisesAreADecodeError() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.notAnImage()))

    #expect(loaded.image == nil)
    #expect(loaded.errorCode == .decode)
  }

  /// `cacheOnly`: the core clears `allowNetwork`, and a miss must not fetch.
  @Test func aCacheMissWithoutNetworkIsNotCached() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.png(), allowNetwork: false))

    #expect(loaded.image == nil)
    #expect(loaded.errorCode == .notCached)
  }

  /// A failed processor fails the load, not falls back to the original.
  @Test func aProcessorThatFailsIsADecodeError() async throws {
    let loaded = await adapter.load(
      adapter.request(for: try Fixture.png(), processorKey: "fails", processor: { _ in nil }))

    #expect(loaded.image == nil)
    #expect(loaded.errorCode == .decode)
  }

  // MARK: Processing

  @Test func theProcessorsResultIsWhatTheLoadDelivers() async throws {
    let replacement = UIGraphicsImageRenderer(size: CGSize(width: 7, height: 5)).image { _ in }
    let box = UncheckedImage(replacement)
    let loaded = await adapter.load(
      adapter.request(for: try Fixture.png(), processorKey: "replace", processor: { _ in box.image }))

    #expect(loaded.image === replacement)
  }

  /// The processor sees the already-bounded decode, not the full bitmap.
  @Test func theProcessorGetsTheImageAtItsDecodeSize() async throws {
    let seen = Recorded<CGSize>()
    _ = await adapter.load(
      adapter.request(
        for: try Fixture.png(), decodeSize: CGSize(width: 20, height: 15), processorKey: "record",
        processor: { image in
          seen.value = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
          return image
        }))

    #expect(seen.value == CGSize(width: 20, height: 15))
  }

  // MARK: Cancel and prefetch

  /// A cancelled load never completes (recycled views rely on this).
  @Test func aCancelledLoadDoesNotComplete() async throws {
    let completed = Recorded<Bool>()
    let task = adapter.loader.loadImage(with: adapter.request(for: try Fixture.png()), progress: nil) {
      _, _, _, _ in completed.value = true
    }

    task.cancel()
    // Well past when an uncancelled load would finish.
    try await Task.sleep(for: .milliseconds(300))

    #expect(completed.value == nil)
  }

  @Test func cancellingTwiceOrAfterCompletionIsHarmless() async throws {
    let request = adapter.request(for: try Fixture.png())
    let task = adapter.loader.loadImage(with: request, progress: nil) { _, _, _, _ in }
    _ = await adapter.load(request)

    task.cancel()
    task.cancel()
  }

  @Test func prefetchReportsWhetherTheImageLoaded() async throws {
    #expect(await adapter.prefetch(adapter.request(for: try Fixture.png())))
    #expect(await adapter.prefetch(adapter.request(for: Fixture.missing())) == false)
  }

  @Test func aPrefetchedImageIsServedFromMemory() async throws {
    let request = adapter.request(for: try Fixture.png(), decodeSize: CGSize(width: 20, height: 15))
    _ = await adapter.prefetch(request)

    let loaded = await adapter.load(request)

    #expect(loaded.fromMemoryCache)
  }

  /// A prefetch (memory write off) decodes nothing into memory. Disk side is
  /// tested on Android, which has an HTTP server.
  @Test func aDiskOnlyPrefetchKeepsNothingInMemory() async throws {
    let file = try Fixture.png()
    let key = UUID().uuidString
    #expect(await adapter.prefetch(adapter.request(for: file, cacheKey: key, memoryCacheWrite: false)))

    let loaded = await adapter.load(adapter.request(for: file, cacheKey: key))

    #expect(loaded.image != nil)
    #expect(!loaded.fromMemoryCache)
  }

  @Test func aDiskOnlyPrefetchStillReportsAFailure() async {
    #expect(await adapter.prefetch(adapter.request(for: Fixture.missing(), memoryCacheWrite: false)) == false)
  }

  /// A memory hit completes synchronously, so a recycled view never flashes blank.
  @Test func aMemoryHitCompletesInsideTheCall() async throws {
    let request = adapter.request(for: try Fixture.png(), decodeSize: CGSize(width: 20, height: 15))
    _ = await adapter.load(request)

    let fromMemory = Recorded<Bool>()
    _ = adapter.loader.loadImage(with: request, progress: nil) { image, _, fromMemoryCache, _ in
      fromMemory.value = image != nil && fromMemoryCache
    }

    #expect(fromMemory.value == true)
  }

  // MARK: Image size (`TurboImage.getSize`)

  @Test func theSizeIsTheImagesOwnInPixels() async throws {
    let result = await adapter.size(adapter.request(for: try Fixture.png()))

    #expect(result.error == nil)
    #expect(result.size == Fixture.size)
  }

  @Test func theSizeFollowsTheExifOrientation() async throws {
    let result = await adapter.size(adapter.request(for: try Fixture.rotatedJpeg()))

    #expect(result.size == CGSize(width: Fixture.size.height, height: Fixture.size.width))
  }

  /// An SVG reports its canvas at screen scale, as on Android.
  @Test func anSvgReportsItsCanvasAtTheScreensScale() async throws {
    let result = await adapter.size(adapter.request(for: try Fixture.svg()))
    let scale = UITraitCollection.current.displayScale

    #expect(result.size == CGSize(width: 120 * scale, height: 80 * scale))
  }

  @Test func aSizeThatCannotBeReadFailsWithTheLoadsCode() async throws {
    let missing = await adapter.size(adapter.request(for: Fixture.missing()))
    let garbage = await adapter.size(adapter.request(for: try Fixture.notAnImage()))

    #expect(missing.error?.domain == TIImageLoadErrorDomain)
    #expect(garbage.error?.code == TIImageLoadError.Code.decode.rawValue)
  }
}

/// A UIImage for a processor block to return. Immutable once made.
private struct UncheckedImage: @unchecked Sendable {
  let image: UIImage
  init(_ image: UIImage) { self.image = image }
}
