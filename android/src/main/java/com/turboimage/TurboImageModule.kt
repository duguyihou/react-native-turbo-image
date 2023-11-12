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

  companion object {
    private const val REACT_CLASS = "TurboImageViewManager"
  }
}
