package com.turboimage

import coil.Coil
import coil.ImageLoader
import coil.annotation.ExperimentalCoilApi
import coil.memory.MemoryCache
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

      resize?.let {
        builder.size(Size(PixelUtil.toPixelFromDIP(it.toFloat()).toInt(), Dimension.Undefined))
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
  }
}
