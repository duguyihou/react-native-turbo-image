// SVG through the adapter. It is decoded with Apple's private CoreSVG into a
// vector `UIImage` (ADR 0008), which has no pixels until something draws it:
// an image view draws it sharp at any size, but a processor needs a bitmap,
// made at the size the request names (`vectorDecodeSize`).
//
// These tests also notice the day a new iOS removes a CoreSVG symbol: every
// one of them then fails with `decode`, which is what an app would see.

import Testing
import TurboImageLoaderAPI
import UIKit

@testable import TurboImageNuke

@MainActor
@Suite(.serialized)
struct SVGTests {
  let adapter = Adapter()
  /// The fixture's canvas (its `viewBox`).
  let canvas = CGSize(width: 120, height: 80)

  @Test func anSVGIsDetectedFromItsBytes() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.svg()))

    #expect(loaded.error == nil)
    #expect(loaded.image?.size == canvas)
    #expect(loaded.animation == nil)
  }

  /// The decode bound is for bitmaps. Shrinking a vector to it would only
  /// rasterise it early; the image view draws it at the view's size anyway.
  @Test func aDecodeBoundLeavesTheVectorAlone() async throws {
    let loaded = await adapter.load(
      adapter.request(for: try Fixture.svg(), decodeSize: CGSize(width: 30, height: 20)))

    #expect(loaded.image?.size == canvas)
  }

  @Test func aProcessorGetsTheVectorDrawnAtTheRequestedSize() async throws {
    let seen = Recorded<CGSize>()
    _ = await adapter.load(
      adapter.request(
        for: try Fixture.svg(), vectorSize: CGSize(width: 60, height: 40), processorKey: "record",
        processor: { image in
          seen.value = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
          return image
        }))

    #expect(seen.value == CGSize(width: 60, height: 40))
  }

  /// No size of the view's to draw for (`center`, or `allowDownscaling` off
  /// without `resize`): the image's own size, at the screen's scale, so it
  /// is as sharp as the vector would be and keeps its size in points.
  @Test func withoutASizeAProcessorGetsTheVectorAtScreenScale() async throws {
    let seen = Recorded<[CGFloat]>()
    _ = await adapter.load(
      adapter.request(
        for: try Fixture.svg(), vectorSize: .zero, displayScale: 2, processorKey: "record",
        processor: { image in
          seen.value = [image.size.width, image.size.height, image.scale]
          return image
        }))

    #expect(seen.value == [canvas.width, canvas.height, 2])
  }

  /// Two views of different sizes showing one processed SVG must not share
  /// an entry: the second would be handed the first one's bitmap.
  @Test func aProcessedSVGIsCachedPerDrawnSize() async throws {
    let file = try Fixture.svg()
    let key = UUID().uuidString
    func request(drawnAt size: CGSize) -> TIImageRequest {
      adapter.request(for: file, cacheKey: key, vectorSize: size, processorKey: "tint", processor: { $0 })
    }
    _ = await adapter.load(request(drawnAt: CGSize(width: 60, height: 40)))

    let other = await adapter.load(request(drawnAt: CGSize(width: 30, height: 20)))
    let same = await adapter.load(request(drawnAt: CGSize(width: 60, height: 40)))

    #expect(other.fromMemoryCache == false)
    #expect(other.pixelSize == CGSize(width: 30, height: 20))
    #expect(same.fromMemoryCache)
  }
}
