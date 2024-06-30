package com.turboimage

import coil.Coil
import coil.annotation.ExperimentalCoilApi
import coil.imageLoader
import coil.request.CachePolicy
import coil.request.ImageRequest
import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule
import okhttp3.Headers

class TurboImageModule(private val context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {

  override fun getName(): String = REACT_CLASS

  @ReactMethod
  fun prefetch(sources: ReadableArray, promise: Promise) {
    sources.toArrayList().forEach { source ->
      val uri = (source as HashMap<*, *>)["uri"] as String
      val headers = source["headers"] as? HashMap<*, *>

      if (headers != null) {
        val requestHeaders = Headers.Builder()
        headers.map { (key, value) ->
          requestHeaders.add(key as String, value as String)
        }
        val request = ImageRequest.Builder(context)
          .headers(requestHeaders.build())
          .data(uri)
          .diskCachePolicy(CachePolicy.ENABLED)
          .memoryCachePolicy(CachePolicy.ENABLED)
          .build()
        context.imageLoader.enqueue(request)
      } else {
        val request = ImageRequest.Builder(context)
          .data(uri)
          .diskCachePolicy(CachePolicy.ENABLED)
          .memoryCachePolicy(CachePolicy.ENABLED)
          .build()
        context.imageLoader.enqueue(request)
      }
    }
    promise.resolve("Success")
  }

  @ReactMethod
  fun clearMemoryCache(promise: Promise) {
    Coil.imageLoader(context).memoryCache?.clear()
    promise.resolve("Success")
  }

  @OptIn(ExperimentalCoilApi::class)
  @ReactMethod
  fun clearDiskCache(promise: Promise) {
    Coil.imageLoader(context).diskCache?.clear()
    promise.resolve("Success")
  }


  companion object {
    private const val REACT_CLASS = "TurboImageViewManager"
  }
}
