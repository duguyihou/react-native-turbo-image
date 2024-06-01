package com.turboimage

import coil.Coil
import coil.annotation.ExperimentalCoilApi
import coil.imageLoader
import coil.request.CachePolicy
import coil.request.ImageRequest
import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule

class TurboImageModule(private val context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {

  override fun getName(): String = REACT_CLASS

  @ReactMethod
  fun prefetch(sources: ReadableArray, promise: Promise) {
    sources.toArrayList().forEach { src ->
      val request = ImageRequest.Builder(context)
        .data(src.toString())
        .diskCachePolicy(CachePolicy.ENABLED)
        .memoryCachePolicy(CachePolicy.ENABLED)
        .build()
      context.imageLoader.enqueue(request)
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
