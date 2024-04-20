package com.turboimage

import android.graphics.Color
import android.widget.ImageView.ScaleType
import coil.Coil
import coil.Coil.imageLoader
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
  override fun createViewInstance(themedConText: ThemedReactContext): TurboImageView {
    val turboImageView = TurboImageView(themedConText)
    requestBuilder =
      ImageRequest.Builder(themedConText).target { turboImageView.setImageDrawable(it) }
    return turboImageView
  }

  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    val request = requestBuilder.data(view.url)
      .memoryCachePolicy(if (view.cachePolicy == "memory") CachePolicy.ENABLED else CachePolicy.DISABLED)
      .diskCachePolicy(if (view.cachePolicy != "memory") CachePolicy.ENABLED else CachePolicy.DISABLED)
      .transformations(transformations)
      .crossfade(view.crossfade)
      .allowHardware(true).build()
    disposable = imageLoader(view.context).enqueue(request)
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

  @ReactProp(name = "fadeDuration")
  fun setCrossfade(view: TurboImageView, crossfade: Int?) {
    if (crossfade != null) {
      view.crossfade = crossfade
    }
  }

  @ReactProp(name = "cachePolicy")
  fun setCachePolicy(view: TurboImageView, cachePolicy: String?) {
    view.cachePolicy = cachePolicy
  }

  companion object {
    private const val REACT_CLASS = "TurboImageView"
    private val RESIZE_MODE = mapOf(
      "contain" to ScaleType.FIT_CENTER,
      "cover" to ScaleType.CENTER_CROP,
      "stretch" to ScaleType.FIT_XY,
      "center" to ScaleType.CENTER_INSIDE
    )
  }
}
