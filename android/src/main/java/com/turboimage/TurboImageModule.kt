package com.turboimage

import coil.Coil
import coil.annotation.ExperimentalCoilApi
import coil.request.ImageRequest
import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule

class TurboImageModule(private val context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {

  override fun getName(): String = REACT_CLASS

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

  @ReactMethod
  fun prefetch(sources: ReadableArray, promise: Promise) {
    sources.toArrayList().forEach { src ->
      val imageLoader = Coil.imageLoader(context)
      val request = ImageRequest.Builder(context)
        .data(src.toString())
        .build()
      imageLoader.enqueue(request)
    }
    promise.resolve("Success")
  }

  companion object {
    private const val REACT_CLASS = "TurboImageViewManager"
  }
}
