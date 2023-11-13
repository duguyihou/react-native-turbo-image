package com.turboimage

import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule

class TurboImageModule(context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {
  override fun getName(): String = REACT_CLASS

  companion object {
    private const val REACT_CLASS = "TurboImageViewManager"
  }
}
