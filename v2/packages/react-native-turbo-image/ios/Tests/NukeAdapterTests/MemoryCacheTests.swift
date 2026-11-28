// Memory tier. One cache key has many Nuke entries (per size and processor)
// and Nuke can't enumerate them, so the adapter keeps a variant index for
// eviction and placeholders; these tests cover it.

import Nuke
import Testing
import TurboImageLoaderAPI
import UIKit

@testable import TurboImageNuke

@MainActor
@Suite(.serialized)
struct MemoryCacheTests {
  let adapter = Adapter()
  let bound = CGSize(width: 20, height: 15)

  // MARK: Reads and writes (the core's cache-policy matrix)

  @Test func aSecondLoadComesFromMemory() async throws {
    let request = adapter.request(for: try Fixture.png(), decodeSize: bound)

    #expect(await adapter.load(request).fromMemoryCache == false)
    #expect(await adapter.load(request).fromMemoryCache)
  }

  /// Nuke reports a variant it processed from the plain image in memory as a
  /// memory hit; the view must still fade it in, as Coil (a disk read) does.
  @Test func aVariantProcessedFromAPlainImageInMemoryIsNotAMemoryHit() async throws {
    let file = try Fixture.png()
    let key = UUID().uuidString
    _ = await adapter.load(adapter.request(for: file, cacheKey: key, decodeSize: bound))

    let processed = await adapter.load(
      adapter.request(
        for: file, cacheKey: key, decodeSize: bound, processorKey: "identity", processor: { $0 }))

    #expect(processed.image != nil)
    #expect(processed.fromMemoryCache == false)
  }

  /// `noCache` and friends: the core clears `memoryCacheWrite`.
  @Test func aLoadThatMayNotWriteLeavesNothingBehind() async throws {
    let file = try Fixture.png()
    let key = UUID().uuidString
    _ = await adapter.load(adapter.request(for: file, cacheKey: key, memoryCacheWrite: false))

    let second = await adapter.load(adapter.request(for: file, cacheKey: key))

    #expect(second.fromMemoryCache == false)
  }

  @Test func aLoadThatMayNotReadIgnoresWhatIsThere() async throws {
    let file = try Fixture.png()
    let key = UUID().uuidString
    _ = await adapter.load(adapter.request(for: file, cacheKey: key))

    let second = await adapter.load(adapter.request(for: file, cacheKey: key, memoryCacheRead: false))

    #expect(second.image != nil)
    #expect(second.fromMemoryCache == false)
  }

  // MARK: One entry per variant

  @Test func eachDecodeSizeIsItsOwnEntry() async throws {
    let file = try Fixture.png()
    let key = UUID().uuidString
    _ = await adapter.load(adapter.request(for: file, cacheKey: key, decodeSize: bound))

    let other = await adapter.load(
      adapter.request(for: file, cacheKey: key, decodeSize: CGSize(width: 10, height: 10)))

    #expect(other.fromMemoryCache == false)
    #expect(other.pixelSize == CGSize(width: 10, height: 8))
  }

  /// Each processing gets its own entry. Checked by identity, since Nuke
  /// reports a variant derived from the cached plain image as a memory hit.
  @Test func eachProcessingIsItsOwnEntry() async throws {
    let file = try Fixture.png()
    let key = UUID().uuidString
    let (blurredImage, tintedImage) = (UncheckedImage(), UncheckedImage())
    let blurred = adapter.request(
      for: file, cacheKey: key, processorKey: "blur", processor: { _ in blurredImage.image })
    _ = await adapter.load(blurred)

    let plain = await adapter.load(adapter.request(for: file, cacheKey: key))
    let tinted = await adapter.load(
      adapter.request(for: file, cacheKey: key, processorKey: "tint", processor: { _ in tintedImage.image }))
    let blurredAgain = await adapter.load(blurred)

    #expect(plain.pixelSize == Fixture.size)
    #expect(tinted.image === tintedImage.image)
    #expect(blurredAgain.image === blurredImage.image)
    #expect(blurredAgain.fromMemoryCache)
  }

  // MARK: Eviction (`TurboImage.dispose`, `clearMemoryCache`)

  @Test func removingAnImageEvictsEveryVariantOfIt() async throws {
    let file = try Fixture.png()
    let key = UUID().uuidString
    // Memory-only variants let the test look without re-caching.
    func variants(memoryOnly: Bool) -> [TIImageRequest] {
      [
        adapter.request(for: file, cacheKey: key, allowNetwork: !memoryOnly),
        adapter.request(for: file, cacheKey: key, decodeSize: bound, allowNetwork: !memoryOnly),
        adapter.request(
          for: file, cacheKey: key, allowNetwork: !memoryOnly, processorKey: "blur", processor: { $0 }),
        adapter.request(
          for: file, cacheKey: key, decodeSize: bound, allowNetwork: !memoryOnly, processorKey: "blur",
          processor: { $0 }),
      ]
    }
    for variant in variants(memoryOnly: false) {
      _ = await adapter.load(variant)
    }
    for variant in variants(memoryOnly: true) {
      #expect(await adapter.load(variant).fromMemoryCache)
    }

    adapter.loader.removeCachedImage(for: variants(memoryOnly: false)[0])

    for variant in variants(memoryOnly: true) {
      #expect(await adapter.load(variant).errorCode == .notCached)
    }
  }

  @Test func removingAnImageLeavesOtherImagesAlone() async throws {
    let kept = adapter.request(for: try Fixture.png(), decodeSize: bound)
    let removed = adapter.request(for: try Fixture.png(), decodeSize: bound)
    _ = await adapter.loadTogether([kept, removed])

    adapter.loader.removeCachedImage(for: removed)

    #expect(await adapter.load(kept).fromMemoryCache)
  }

  // MARK: The index stays bounded

  /// A fresh-key variant `n` pixels wide: a new index entry.
  private func variant(_ n: Int, of file: URL, on adapter: Adapter) -> TIImageRequest {
    adapter.request(for: file, decodeSize: CGSize(width: n, height: n))
  }

  /// Entries Nuke evicted are swept once past the threshold, so the index
  /// stays bounded.
  @Test func variantsNukeHasEvictedAreSweptFromTheIndex() async throws {
    let file = try Fixture.png()
    let small = Adapter(loader: NukeImageLoader(minimumSweepThreshold: 4))
    for n in 1...4 {
      _ = await small.load(variant(n, of: file, on: small))
    }
    #expect(small.loader.variantCount == 4)

    // Evict behind the index's back.
    small.loader.pipeline.cache.removeAll(caches: .memory)
    _ = await small.load(variant(5, of: file, on: small))

    #expect(small.loader.variantCount == 1)
  }

  /// A sweep keeps variants still in memory, including one still loading.
  @Test func variantsStillInMemorySurviveASweep() async throws {
    let file = try Fixture.png()
    let small = Adapter(loader: NukeImageLoader(minimumSweepThreshold: 4))
    let requests = (1...5).map { variant($0 * 2, of: file, on: small) }
    for request in requests {
      _ = await small.load(request)
    }

    #expect(small.loader.variantCount == 5)
    // Still found by key, and still evicted by `dispose`.
    #expect(small.loader.memoryCachedImage(forKey: requests[4].cacheKey) != nil)
    small.loader.removeCachedImage(for: requests[4])
    #expect(small.loader.memoryCachedImage(forKey: requests[4].cacheKey) == nil)
    #expect(small.loader.variantCount == 4)
  }

  // MARK: Sizes (`TurboImage.configureCache`)

  /// Sizes reach a new adapter, and are refused once a loader exists.
  @Test func configuredSizesReachTheAdapterOnlyBeforeALoaderExists() throws {
    #expect(TIImageLoaderRegistry.configureCache(withMaxDiskSize: 50_000_000, maxMemoryCost: 4_000_000))
    let configured = NukeImageLoader()
    #expect(TIImageLoaderRegistry.configureCache(withMaxDiskSize: 0, maxMemoryCost: 0))

    let memory = try #require(configured.pipeline.configuration.imageCache as? ImageCache)
    #expect(memory.costLimit == 4_000_000)
    // Applies to the key cache; the HTTP cache keeps its default.
    let disk = try #require(configured.pipeline.configuration.dataCache as? DataCache)
    #expect(disk.sizeLimit == 50_000_000)
    #expect(configured.urlCache.diskCapacity == NukeImageLoader.diskCacheBytes)

    TIImageLoaderRegistry.setSharedLoaderForTesting(configured)
    defer { TIImageLoaderRegistry.setSharedLoaderForTesting(nil) }
    #expect(TIImageLoaderRegistry.configureCache(withMaxDiskSize: 1, maxMemoryCost: 1) == false)
    #expect(TIImageLoaderRegistry.cacheMaxMemoryCost == 0)
  }

  @Test func clearingTheMemoryCacheEvictsEverything() async throws {
    let request = adapter.request(for: try Fixture.png(), decodeSize: bound)
    _ = await adapter.load(request)

    adapter.loader.clearMemoryCache()

    // Looked up first: the load below puts the image back.
    #expect(adapter.loader.memoryCachedImage(forKey: request.cacheKey) == nil)
    #expect(await adapter.load(request).fromMemoryCache == false)
  }

  // MARK: The `memoryCacheKey` placeholder

  @Test func aCachedImageIsFoundByItsKey() async throws {
    let request = adapter.request(for: try Fixture.png())
    let loaded = await adapter.load(request)

    #expect(adapter.loader.memoryCachedImage(forKey: request.cacheKey) === loaded.image)
    #expect(adapter.loader.memoryCachedImage(forKey: "never loaded") == nil)
  }

  /// Any size will do for a placeholder.
  @Test func aDownscaledImageIsFoundByItsKey() async throws {
    let request = adapter.request(for: try Fixture.png(), decodeSize: bound)
    let loaded = await adapter.load(request)

    #expect(adapter.loader.memoryCachedImage(forKey: request.cacheKey) === loaded.image)
  }

  /// A blurred or tinted variant must not stand in for the image.
  @Test func aProcessedVariantIsNotAPlaceholder() async throws {
    let request = adapter.request(
      for: try Fixture.png(), decodeSize: bound, processorKey: "blur", processor: { $0 })
    _ = await adapter.load(request)

    #expect(adapter.loader.memoryCachedImage(forKey: request.cacheKey) == nil)
  }
}

/// A distinct image per processor, to tell results apart.
private struct UncheckedImage: @unchecked Sendable {
  let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
}
