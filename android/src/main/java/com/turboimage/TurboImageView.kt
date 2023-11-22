package com.turboimage

import android.annotation.SuppressLint
import android.graphics.Color
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import androidx.lifecycle.LifecycleObserver
import coil.Coil
import coil.drawable.CrossfadeDrawable
import coil.request.ImageRequest

import com.facebook.react.uimanager.ThemedReactContext

@SuppressLint("ViewConstructor")
class TurboImageView(private val reactContext: ThemedReactContext) :
  AppCompatImageView(reactContext) {
  private var url: String? = null
  private var base64Placeholder: String? = null
  private var fadeDuration: Int? = null

  init {
    setBackgroundColor(Color.BLUE)
  }

  fun setUrl(urlString: String?) {
    url = urlString
  }

  fun setBase64Placeholder(placeholder: String?) {
    base64Placeholder = placeholder
  }

  fun setCrossfade(duration: Int = CrossfadeDrawable.DEFAULT_DURATION) {
    fadeDuration = duration
  }
}
