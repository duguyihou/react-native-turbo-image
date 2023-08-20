package com.turboimage

import coil.Coil
import coil.annotation.ExperimentalCoilApi
import coil.request.CachePolicy
import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod

class TurboImageModule(private val context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {
  override fun getName(): String = REACT_CLASS

  @ReactMethod
  fun clearAllCache() {
    val loader = Coil.imageLoader(context)
    if (loader.defaults.memoryCachePolicy != CachePolicy.DISABLED) {
      clearMemoryCache()
    }
    if (loader.defaults.diskCachePolicy != CachePolicy.DISABLED) {
      clearDiskCache()
    }
  }

  @ReactMethod
  fun clearMemoryCache() {
    Coil.imageLoader(context).memoryCache?.clear()
  }

  @OptIn(ExperimentalCoilApi::class)
  @ReactMethod
  fun clearDiskCache() {
    Coil.imageLoader(context).diskCache?.clear()
  }

  companion object {
    private const val REACT_CLASS = "TurboImageModule"
  }
}
