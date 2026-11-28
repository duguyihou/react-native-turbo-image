// SVG decodes via private CoreSVG to a vector `UIImage` (ADR 0008); a
// processor gets it rasterized at `vectorDecodeSize`. If iOS drops a CoreSVG
// symbol, these all fail with `decode`.

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

  /// The decode bound is for bitmaps; a vector stays a vector.
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

  /// No view size: own size at screen scale, same size in points.
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

  /// Different drawn sizes must not share a cache entry.
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
