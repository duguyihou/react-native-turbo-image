package com.turboimage

import android.annotation.SuppressLint
import androidx.appcompat.widget.AppCompatImageView
import coil.drawable.CrossfadeDrawable
import coil.size.Size
import coil.transform.Transformation

import com.facebook.react.uimanager.ThemedReactContext

@SuppressLint("ViewConstructor")
class TurboImageView(reactContext: ThemedReactContext) : AppCompatImageView(reactContext) {
  var src: String? = null
  var cachePolicy: String? = "memory"
  var crossfade: Int = CrossfadeDrawable.DEFAULT_DURATION
  var blurhash: String? = null
  var resize: Size? = null

  val transformations: MutableList<Transformation> = mutableListOf()
}
