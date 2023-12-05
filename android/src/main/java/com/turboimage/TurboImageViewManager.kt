package com.turboimage

import android.graphics.Color
import android.widget.ImageView
import coil.Coil
import coil.request.CachePolicy
import coil.request.Disposable
import coil.request.ImageRequest
import coil.transform.Transformation
import com.commit451.coiltransformations.ColorFilterTransformation
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class TurboImageViewManager : SimpleViewManager<TurboImageView>() {
  override fun getName() = REACT_CLASS
  private lateinit var requestBuilder: ImageRequest.Builder
  private var disposable: Disposable? = null
  private val transformations: MutableList<Transformation> = mutableListOf()
  override fun createViewInstance(p0: ThemedReactContext): TurboImageView {
    val instance = TurboImageView(p0)
    requestBuilder = ImageRequest.Builder(p0).target { instance.setImageDrawable(it) }
    return instance
  }

  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    val placeholder = view.base64Placeholder?.let { Base64Placeholder.toDrawable(view.context, it) }
    val color = view.tintColor?.let { Color.parseColor(it) }
    if (color != null) {
      transformations.add(ColorFilterTransformation(color))
    }
    val request = requestBuilder
      .data(view.url)
      .placeholder(placeholder)
      .diskCachePolicy(CachePolicy.DISABLED)
      .transformations(transformations)
      .crossfade(view.crossfade)
      .build()
    disposable = Coil.imageLoader(view.context).enqueue(request)
  }

  override fun onDropViewInstance(view: TurboImageView) {
    super.onDropViewInstance(view)
    disposable?.let {
      if (!it.isDisposed) it.dispose()
    }
  }

  @ReactProp(name = "url")
  fun setUrl(view: TurboImageView, url: String) {
    view.url = url
  }

  @ReactProp(name = "resizeMode")
  fun setResizeMode(view: TurboImageView, resizeMode: String?) {
    view.scaleType = RESIZE_MODE[resizeMode]
  }

  @ReactProp(name = "base64Placeholder")
  fun setBase64Placeholder(view: TurboImageView, base64Placeholder: String?) {
    view.base64Placeholder = base64Placeholder
  }

  @ReactProp(name = "fadeDuration")
  fun setCrossfade(view: TurboImageView, crossfade: Int?) {
    if (crossfade != null) {
      view.crossfade = crossfade
    }
  }

  @ReactProp(name = "tintColor")
  fun setTintColor(view: TurboImageView, tintColor: String?) {
    if (tintColor != null) {
      view.tintColor = tintColor
    }
  }

  companion object {
    private const val REACT_CLASS = "TurboImageView"
    private val RESIZE_MODE = mapOf(
      "contain" to ImageView.ScaleType.FIT_CENTER,
      "cover" to ImageView.ScaleType.CENTER_CROP,
      "stretch" to ImageView.ScaleType.FIT_XY,
      "center" to ImageView.ScaleType.CENTER_INSIDE
    )
  }
}
