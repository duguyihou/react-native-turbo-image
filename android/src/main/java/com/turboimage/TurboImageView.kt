package com.turboimage

import android.annotation.SuppressLint
import androidx.appcompat.widget.AppCompatImageView
import coil.drawable.CrossfadeDrawable
import coil.size.Size
import coil.transform.CircleCropTransformation
import coil.transform.RoundedCornersTransformation
import coil.transform.Transformation
import com.commit451.coiltransformations.BlurTransformation
import com.commit451.coiltransformations.ColorFilterTransformation

import com.facebook.react.uimanager.ThemedReactContext

@SuppressLint("ViewConstructor")
class TurboImageView(private val reactContext: ThemedReactContext) :
  AppCompatImageView(reactContext) {
  var src: String? = null
  var cachePolicy: String? = "memory"
  var crossfade: Int = CrossfadeDrawable.DEFAULT_DURATION

  var resize: Size? = null
  var borderRadius: Float? = null
  var rounded: Boolean? = null
  var blur: Float? = null
  var monochrome: Int? = null
  var tint: Int? = null

  val transformations: MutableList<Transformation>
    get() {
      val list = mutableListOf<Transformation>()
      tint?.let { list.add(ColorFilterTransformation(it)) }
      monochrome?.let { list.add(MonochromeTransformation(it)) }
      blur?.let { list.add(BlurTransformation(reactContext, it)) }
      rounded?.let { list.add(CircleCropTransformation()) }
      borderRadius?.let { list.add(RoundedCornersTransformation(it)) }
      return list
    }
}
