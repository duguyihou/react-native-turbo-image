package com.turboimage

import android.annotation.SuppressLint
import androidx.appcompat.widget.AppCompatImageView
import coil.size.Size
import coil.transform.CircleCropTransformation
import coil.transform.RoundedCornersTransformation
import coil.transform.Transformation
import com.commit451.coiltransformations.BlurTransformation
import com.commit451.coiltransformations.ColorFilterTransformation
import com.facebook.react.uimanager.PixelUtil

import com.facebook.react.uimanager.ThemedReactContext

@SuppressLint("ViewConstructor")
class TurboImageView(private val reactContext: ThemedReactContext) :
  AppCompatImageView(reactContext) {
  var src: String? = null
  var cachePolicy: String? = "memory"
  var crossfade: Int? = null

  var resize: Size? = null
  var borderRadius: Int? = null
  var rounded: Boolean? = null
  var blur: Int? = null
  var monochrome: Int? = null
  var tint: Int? = null

  val transformations: MutableList<Transformation>
    get() {
      val list = mutableListOf<Transformation>()

      borderRadius?.let {
        val radii = PixelUtil.toPixelFromDIP(it.toFloat())
        list.add(RoundedCornersTransformation(radii))
      }

      rounded?.let {
        list.add(CircleCropTransformation())
      }

      blur?.let {
        list.add(BlurTransformation(reactContext, it.toFloat()))
      }

      monochrome?.let {
        list.add(MonochromeTransformation(it))
      }

      tint?.let {
        list.add(ColorFilterTransformation(it))
      }

      return list
    }
}
