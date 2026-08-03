package com.turboimage

import coil.Coil
import coil.ImageLoader
import coil.annotation.ExperimentalCoilApi
import coil.memory.MemoryCache
import coil.request.CachePolicy
import coil.request.ImageRequest
import coil.size.Dimension
import coil.size.Size
import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.uimanager.PixelUtil
import okhttp3.Headers

class TurboImageModule(private val context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {
  private var imageLoader: ImageLoader? = null

  override fun getName(): String = REACT_CLASS

  @ReactMethod
  fun prefetch(sources: ReadableArray, cachePolicy: String, promise: Promise) {
    var completedRequestCount = 0
    fun handleRequestCount() {
      completedRequestCount++
      if (sources.size() == completedRequestCount) {
        promise.resolve(true)
      }
    }

    val imageRequests = sources.toArrayList().map { source ->
      val uri = (source as HashMap<*, *>)["uri"] as String
      val headers = source["headers"] as? HashMap<*, *>
      val resize = source["resize"] as? Double
      val cacheKey = source["cacheKey"] as? String
      TurboImageCacheKeyIndex.register(context, cacheKey ?: uri)

      val builder = ImageRequest.Builder(context)
        .data(uri)
        .listener(
          onSuccess = { _, _ -> handleRequestCount() },
          onError = { _, _ -> handleRequestCount() }
        )

      if (headers != null) {
        val headersBuilder = Headers.Builder()
        headers.map { (key, value) ->
          headersBuilder.add(key as String, value as String)
        }
        builder.headers(headersBuilder.build())
      }

      // A "dataCache" prefetch exists to fill the DISK cache ahead of the viewport, and the disk
      // entry holds the ORIGINAL bytes regardless of what size the request asks for. So the
      // request is deliberately decoded tiny and thrown away:
      //
      //   - decoding at the display size allocates a full bitmap per prefetched page (tens of MB
      //     for a webtoon strip) for a page that is not on screen and may never be reached;
      //   - keeping it in the memory cache then retains all of them at once, which on a low-RAM
      //     device is enough on its own to get the process killed by lowmemorykiller.
      //
      // Writing the disk entry by hand instead (raw OkHttp -> DiskCache.openEditor) does NOT
      // work: Coil stores response metadata alongside the data and discards any entry that has
      // only the data half, so those entries are evicted on read and every page loads cold.
      // Letting Coil do the write is what keeps the entry valid; only the decode is made cheap.
      //
      // "memoryWarm" is the opposite trade and exists for the handful of pages just outside the
      // viewport: decode at display size into the memory cache so the page appears instantly when
      // scrolled to. Costs a full bitmap each, so the caller is expected to use it for a small,
      // bounded window and "dataCache" for everything beyond it.
      if (cachePolicy == "dataCache") {
        builder.size(Size(PREFETCH_DECODE_PX, Dimension.Undefined))
        builder.memoryCachePolicy(CachePolicy.DISABLED)
      } else {
        resize?.let {
          builder.size(Size(PixelUtil.toPixelFromDIP(it.toFloat()).toInt(), Dimension.Undefined))
        }
      }

      builder.build()
    }
    imageLoader = Coil.imageLoader(context).newBuilder()
      .respectCacheHeaders(cachePolicy == "urlCache")
      .build()
    imageRequests.forEach { imageRequest ->
      imageLoader?.enqueue(imageRequest)
    }
  }

  @ReactMethod
  fun clearMemoryCache(sources: ReadableArray?, promise: Promise) {
    val memoryCache = Coil.imageLoader(context).memoryCache
    if (sources == null || sources.size() == 0) {
      memoryCache?.clear()
      promise.resolve("Success")
      return
    }
    try {
      sources.toArrayList().forEach { raw ->
        val source = raw as HashMap<*, *>
        if (isPrefixFilter(source)) {
          val includePrefix = source["include_prefix"] as? String
          val excludePrefix = source["exclude_prefix"] as? String
          TurboImageCacheKeyIndex.keys(context, includePrefix, excludePrefix).forEach { key ->
            memoryCache?.remove(MemoryCache.Key(key))
          }
        } else {
          val uri = source["uri"] as String
          val cacheKey = source["cacheKey"] as? String
          memoryCache?.remove(MemoryCache.Key(cacheKey ?: uri))
        }
      }
      promise.resolve("Success")
    } catch (e: Exception) {
      promise.reject("clearMemoryCache", e)
    }
  }

  @OptIn(ExperimentalCoilApi::class)
  @ReactMethod
  fun clearDiskCache(sources: ReadableArray?, promise: Promise) {
    val diskCache = Coil.imageLoader(context).diskCache
    if (sources == null || sources.size() == 0) {
      diskCache?.clear()
      TurboImageCacheKeyIndex.clear(context)
      promise.resolve("Success")
      return
    }
    try {
      sources.toArrayList().forEach { raw ->
        val source = raw as HashMap<*, *>
        if (isPrefixFilter(source)) {
          val includePrefix = source["include_prefix"] as? String
          val excludePrefix = source["exclude_prefix"] as? String
          val matched = TurboImageCacheKeyIndex.keys(context, includePrefix, excludePrefix)
          matched.forEach { key -> diskCache?.remove(key) }
          TurboImageCacheKeyIndex.remove(context, matched)
        } else {
          val uri = source["uri"] as String
          val cacheKey = source["cacheKey"] as? String
          diskCache?.remove(cacheKey ?: uri)
        }
      }
      promise.resolve("Success")
    } catch (e: Exception) {
      promise.reject("clearDiskCache", e)
    }
  }

  // A prefix filter is `{ include_prefix?, exclude_prefix? }` with no `uri` -
  // distinguishes it from a normal source map passed to clear* calls.
  private fun isPrefixFilter(source: HashMap<*, *>): Boolean {
    return source["uri"] == null && (source["include_prefix"] != null || source["exclude_prefix"] != null)
  }


  companion object {
    private const val REACT_CLASS = "TurboImageViewManager"

    // Decode width for prefetch requests. Small enough that the bitmap is irrelevant (BitmapFactory
    // downsamples via inSampleSize, so it is also cheap to produce), non-zero because a request
    // still has to decode successfully for Coil to commit the disk entry.
    private const val PREFETCH_DECODE_PX = 32
  }
}
