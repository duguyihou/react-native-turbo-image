package com.turboimage

import android.annotation.SuppressLint
import androidx.appcompat.widget.AppCompatImageView
import coil.drawable.CrossfadeDrawable

import com.facebook.react.uimanager.ThemedReactContext

@SuppressLint("ViewConstructor")
class TurboImageView(reactContext: ThemedReactContext) : AppCompatImageView(reactContext) {
  var url: String? = null
  var base64Placeholder: String? = null
  var crossfade: Int = CrossfadeDrawable.DEFAULT_DURATION
  var tintColor: String? = null
}
