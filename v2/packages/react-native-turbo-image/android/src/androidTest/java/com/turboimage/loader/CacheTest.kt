package com.turboimage.loader

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import coil3.decode.DataSource
import coil3.memory.MemoryCache
import coil3.request.SuccessResult
import com.turboimage.core.CachePolicy
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.Processing
import com.turboimage.core.ResizeMode
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The adapter's cache tiers, the part of the cross-platform contract that is
 * easiest to get subtly wrong (RFC §4.2): which policy reads and writes
 * which tier, what eviction reaches, and that `urlCache` obeys
 * `Cache-Control` while every other policy ignores it.
 *
 * Whether a load reached the network is read from the fixture server's
 * request count; the seam's listener does not say. A tier is isolated by
 * emptying the other: [clearMemoryCache] leaves only the disk to hit.
 */
@RunWith(AndroidJUnit4::class)
class CacheTest : AdapterTest() {
  // MARK: The policies (the core's cache matrix)

  @Test
  fun defaultKeepsTheImageInMemoryAndOnDisk() {
    val uri = photo()
    load(resolve(uri))

    assertTrue(load(resolve(uri)).succeeded)
    assertEquals("a memory hit", 1, requestsReceived(uri))

    clearMemoryCache()
    assertTrue(load(resolve(uri)).succeeded)
    assertEquals("a disk hit", 1, requestsReceived(uri))
  }

  @Test
  fun memoryOnlyNeverReachesTheDisk() {
    val uri = photo()
    load(resolve(uri, CachePolicy.MEMORY_ONLY))
    load(resolve(uri, CachePolicy.MEMORY_ONLY))
    assertEquals("a memory hit", 1, requestsReceived(uri))

    clearMemoryCache()
    assertFalse("nothing was written to disk", isCached(uri))
  }

  @Test
  fun noCacheFetchesEveryTimeAndStoresNothing() {
    val uri = photo()
    load(resolve(uri, CachePolicy.NO_CACHE))
    load(resolve(uri, CachePolicy.NO_CACHE))

    assertEquals(2, requestsReceived(uri))
    assertFalse(isCached(uri))
  }

  @Test
  fun cacheOnlyServesWhatAnotherPolicyStored() {
    val uri = photo()
    load(resolve(uri))
    clearMemoryCache()

    assertTrue(load(resolve(uri, CachePolicy.CACHE_ONLY)).succeeded)
    assertEquals(1, requestsReceived(uri))
  }

  /** The keyed disk tier ignores `Cache-Control`: only `urlCache` obeys it. */
  @Test
  fun defaultIgnoresNoStore() {
    val uri = photo("cache/nostore")
    load(resolve(uri))
    clearMemoryCache()

    assertTrue(isCached(uri))
    assertEquals(1, requestsReceived(uri))
  }

  // MARK: `urlCache`: an HTTP cache of its own

  @Test
  fun urlCacheServesAFreshResponseWithoutAsking() {
    val uri = photo("cache/fresh")
    load(resolve(uri, CachePolicy.URL_CACHE))
    clearMemoryCache()

    assertTrue(load(resolve(uri, CachePolicy.URL_CACHE)).succeeded)
    assertEquals("max-age=3600 is still fresh", 1, requestsReceived(uri))
  }

  @Test
  fun urlCacheNeverStoresNoStore() {
    val uri = photo("cache/nostore")
    load(resolve(uri, CachePolicy.URL_CACHE))
    clearMemoryCache()

    load(resolve(uri, CachePolicy.URL_CACHE))
    assertEquals(2, requestsReceived(uri))
    assertEquals("neither load was conditional", 0, conditionalRequestsReceived(uri))
  }

  @Test
  fun urlCacheRevalidatesAStaleResponse() {
    val uri = photo("cache/revalidate")
    load(resolve(uri, CachePolicy.URL_CACHE))
    clearMemoryCache()

    assertTrue(load(resolve(uri, CachePolicy.URL_CACHE)).succeeded)
    assertEquals(2, requestsReceived(uri))
    assertEquals("the second asked with If-None-Match, and got a 304", 1, conditionalRequestsReceived(uri))
  }

  /** The two disk stores never see each other's entries (RFC §4.2a). */
  @Test
  fun urlCacheAndTheKeyedDiskCacheAreSeparate() {
    val uri = photo("cache/fresh")
    load(resolve(uri, CachePolicy.URL_CACHE))
    clearMemoryCache()

    assertFalse("cacheOnly reads the keyed store, which urlCache did not write", isCached(uri))
  }

  // MARK: Variants

  /** A processed image must never be handed to a view that asked for the plain one. */
  @Test
  fun eachProcessingIsItsOwnMemoryEntryOverOneOriginal() {
    val uri = photo()
    val blurred = load(resolve(uri, processing = Processing(blur = 4.0)))
    val plain = load(resolve(uri))

    assertTrue(blurred.succeeded && plain.succeeded)
    assertEquals("the plain image came from the disk original", 1, requestsReceived(uri))
    assertNotNull(memoryCached(resolve(uri)))
  }

  // MARK: Eviction (`TurboImage.dispose`, `clearMemoryCache`, `clearDiskCache`)

  @Test
  fun removingAnImageEvictsItFromBothTiers() {
    val uri = photo()
    val blurred = resolve(uri, processing = Processing(blur = 4.0))
    load(resolve(uri))
    load(blurred)

    remove(resolve(uri))

    assertNull(memoryCached(resolve(uri)))
    assertFalse(isCached(uri))
    load(blurred)
    assertEquals("the processed variant went too", 2, requestsReceived(uri))
  }

  @Test
  fun removingAnImageEvictsItsHttpCacheEntry() {
    val uri = photo("cache/fresh")
    load(resolve(uri, CachePolicy.URL_CACHE))

    remove(resolve(uri))
    load(resolve(uri, CachePolicy.URL_CACHE))

    assertEquals(2, requestsReceived(uri))
  }

  @Test
  fun removingAnImageLeavesOtherImagesAlone() {
    val kept = photo()
    val removed = photo()
    load(resolve(kept))
    load(resolve(removed))

    remove(resolve(removed))

    assertNotNull(memoryCached(resolve(kept)))
    assertTrue(isCached(kept))
  }

  @Test
  fun clearingTheDiskCacheLeavesMemory() {
    val uri = photo()
    load(resolve(uri))

    clearDiskCache()

    assertNotNull("memory is a separate call", memoryCached(resolve(uri)))
    clearMemoryCache()
    assertFalse(isCached(uri))
  }

  // MARK: Original-size entries

  /**
   * Coil never accepts a "sampled" bitmap, which an SVG drawing is, for an
   * original-size request, unless the key records that size. Without it,
   * an SVG under `center` was drawn again from the disk on every load.
   */
  @Test
  fun anOriginalSizeSvgIsServedFromMemory() {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val request = resolve(fixture("logo.svg"), resizeMode = ResizeMode.CENTER)
    val sources =
      (1..2).map {
        val result = runBlocking { adapter.imageLoader.execute(request.toCoilRequest(context, view = null).build()) }
        (result as SuccessResult).dataSource
      }

    assertEquals(listOf(DataSource.NETWORK, DataSource.MEMORY_CACHE), sources)
  }

  /**
   * An original-size entry (here a `'memory'` prefetch) is not handed to a
   * view-sized load: the thumbnail gets its own small decode, from the disk.
   */
  @Test
  fun aViewIsNotGivenAPrefetchedFullSizeBitmap() {
    val uri = photo()
    assertTrue(prefetch(resolve(uri, allowDownscaling = false)))

    val thumbnail = load(resolve(uri))

    assertEquals(VIEW_WIDTH to VIEW_HEIGHT, thumbnail.width to thumbnail.height)
    assertEquals("from the disk", 1, requestsReceived(uri))
  }

  // MARK: The `memoryCacheKey` placeholder

  @Test
  fun aCachedImageIsFoundByItsKey() {
    val uri = photo()
    load(resolve(uri))

    assertNotNull(memoryCached(resolve(uri)))
    assertNull(memoryCached(resolve(photo())))
  }

  /**
   * What `memoryCachedDrawable`'s one-lookup path relies on: with an
   * explicit `memoryCacheKey`, Coil keys an unprocessed entry by the cache
   * key alone, whatever size it was decoded at. Were that to change (a Coil
   * upgrade), lookups would silently fall back to scanning every key.
   */
  @Test
  fun anUnprocessedEntryIsKeyedByTheCacheKeyAlone() {
    val request = resolve(photo())
    load(request)

    val keys = onMain { adapter.imageLoader.memoryCache!!.keys }
    assertTrue(MemoryCache.Key(request.cacheKey) in keys)
  }

  /** A blurred or tinted variant must not stand in for the image. */
  @Test
  fun aProcessedVariantIsNotAPlaceholder() {
    val uri = photo()
    load(resolve(uri, processing = Processing(blur = 4.0)))

    assertNull(memoryCached(resolve(uri)))
  }

  @Test
  fun aFailedLoadCachesNothing() {
    val uri = "$BASE/no-such-route/${java.util.UUID.randomUUID()}.jpg"
    assertEquals(LoadErrorCode.NETWORK, load(resolve(uri)).error)

    assertNull(memoryCached(resolve(uri)))
  }

  // MARK: Sizes (`TurboImage.configureCache`)

  @Test
  fun aConfiguredMemorySizeIsTheOneCoilIsBuiltWith() {
    // Memory only: a second disk cache on the shared adapter's directory
    // would clash with it.
    val loader = buildImageLoader(context(), CacheSizes(maxMemoryCost = 4_000_000))
    assertEquals(4_000_000L, loader.memoryCache?.maxSize)
  }

  @Test
  fun sizesAreRefusedOnceTheAdapterExists() {
    onMain { TurboImageLoaders.get(context()) }
    assertFalse(onMain { TurboImageLoaders.configureCache(CacheSizes(maxDiskSize = 1)) })
  }

  private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
