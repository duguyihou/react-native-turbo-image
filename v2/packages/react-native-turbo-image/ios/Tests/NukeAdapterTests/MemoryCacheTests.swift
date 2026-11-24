// The adapter's memory tier: which loads hit it, which entries are separate,
// and what eviction reaches.
//
// Nuke keys a memory entry by (imageID, thumbnail, processors), so one cache
// key has an entry per decode size and per processed variant, and Nuke's
// cache cannot be enumerated. The adapter keeps an index of the variants it
// has seen so that `removeCachedImage` and the `memoryCacheKey` placeholder
// can find them; these tests are what holds that index to its job.

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

  /// A processed image must never be handed to a view that asked for the
  /// plain one, or for another processing of it.
  ///
  /// Told apart by the image, not by `fromMemoryCache`: Nuke makes a
  /// processed variant from the plain image when that is in memory, and
  /// reports the result as a memory hit although the variant was not cached.
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
    // Every variant of one key, as a normal load or as a memory-only one.
    // The memory-only form is how the test looks without loading: a normal
    // load of the plain image would put it back, and Nuke would then make
    // the processed variants from it.
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

  /// A sizes-only variant of a fresh key, `n` pixels wide: each call is a
  /// new entry in the index.
  private func variant(_ n: Int, of file: URL, on adapter: Adapter) -> TIImageRequest {
    adapter.request(for: file, decodeSize: CGSize(width: n, height: n))
  }

  /// Nuke's LRU evicts entries the index cannot see go. Past its threshold
  /// the index drops them, so it does not grow with every image a long
  /// list has ever shown.
  @Test func variantsNukeHasEvictedAreSweptFromTheIndex() async throws {
    let file = try Fixture.png()
    let small = Adapter(loader: NukeImageLoader(minimumSweepThreshold: 4))
    for n in 1...4 {
      _ = await small.load(variant(n, of: file, on: small))
    }
    #expect(small.loader.variantCount == 4)

    // As memory pressure or the LRU would: behind the index's back.
    small.loader.pipeline.cache.removeAll(caches: .memory)
    _ = await small.load(variant(5, of: file, on: small))

    #expect(small.loader.variantCount == 1)
  }

  /// A sweep keeps every variant still in memory, so eviction and the
  /// placeholder lookup keep finding them. That includes one whose load was
  /// still running when the sweep ran (its entry was not written yet).
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

  /// The registry hands the sizes to the adapter it creates, and refuses
  /// them once a loader exists. The suite never registers a loader, so the
  /// registry starts empty; it is left as found.
  @Test func configuredSizesReachTheAdapterOnlyBeforeALoaderExists() throws {
    #expect(TIImageLoaderRegistry.configureCache(withMaxDiskSize: 50_000_000, maxMemoryCost: 4_000_000))
    let configured = NukeImageLoader()
    #expect(TIImageLoaderRegistry.configureCache(withMaxDiskSize: 0, maxMemoryCost: 0))

    let memory = try #require(configured.pipeline.configuration.imageCache as? ImageCache)
    #expect(memory.costLimit == 4_000_000)
    // The disk size is the store every policy but urlCache uses; the HTTP
    // cache keeps its own 150 MB.
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

  /// A view usually caches the image at its own size, under a key that
  /// includes that size. Any size will do for a placeholder.
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

/// A distinct image for a processor block to return, so a test can tell
/// which processor produced what it was handed. Immutable once made.
private struct UncheckedImage: @unchecked Sendable {
  let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
}
