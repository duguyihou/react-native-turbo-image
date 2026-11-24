package com.turboimage.loader

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import coil3.decode.DataSource
import coil3.memory.MemoryCache
import coil3.request.SuccessResult
import com.turboimage.core.CachePolicy
import com.turboimage.core.ImageRequest
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.Processing
import com.turboimage.core.ResizeMode
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The adapter's cache tiers: which policy reads and writes which tier, what
 * eviction reaches, and that only `urlCache` obeys `Cache-Control`. Network
 * hits are counted by the fixture server.
 */
@RunWith(AndroidJUnit4::class)
internal class CacheTest : AdapterTest() {
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

  /** The two disk stores never see each other's entries. */
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

  /** An SVG under `center` must hit memory, not be redrawn from disk each load. */
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

  /** A full-size entry is not reused for a view-sized load; it decodes from disk. */
  @Test
  fun aViewIsNotGivenAPrefetchedFullSizeBitmap() {
    val uri = photo()
    assertTrue(prefetch(resolve(uri, allowDownscaling = false)))

    val thumbnail = load(resolve(uri))

    assertEquals(VIEW_WIDTH to VIEW_HEIGHT, thumbnail.width to thumbnail.height)
    assertEquals("from the disk", 1, requestsReceived(uri))
  }

  // MARK: Prefetching

  /** A prefetch resolves the original, under the view's key. */
  @Test
  fun aPrefetchResolvesTheOriginalUnderTheViewsKey() {
    val uri = photo()
    val prefetched = TurboImageCore.resolveForCache(uri, null, CachePolicy.DEFAULT, emptyList()) as ResolvedRequest
    val view = resolve(uri, processing = Processing(resize = 120.0, blur = 4.0), resizeMode = ResizeMode.COVER)

    assertEquals(view.cacheKey, prefetched.cacheKey)
    assertEquals("", prefetched.processorKey)
    assertEquals(ResolvedRequest.DecodeSize.Original, prefetched.decode)
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
   * `memoryCachedDrawable`'s single lookup relies on this; if a Coil upgrade
   * breaks it, lookups silently fall back to scanning every key.
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
    // Memory only: a second disk cache would clash with the shared adapter's.
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
