package com.turboimage

import android.widget.ImageView
import coil.Coil
import coil.drawable.CrossfadeDrawable
import coil.request.Disposable
import coil.request.ImageRequest
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class TurboImageViewManager : SimpleViewManager<TurboImageView>() {
  override fun getName() = REACT_CLASS
  private lateinit var requestBuilder: ImageRequest.Builder
  private var disposable: Disposable? = null

  override fun createViewInstance(p0: ThemedReactContext): TurboImageView {
    val instance = TurboImageView(p0)
    requestBuilder = ImageRequest.Builder(p0).target { instance.setImageDrawable(it) }
    return instance
  }

  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    val request = requestBuilder.build()
    disposable = Coil.imageLoader(view.context).enqueue(request)
    print("🐵 ---- disposable $disposable")
  }

  override fun onDropViewInstance(view: TurboImageView) {
    super.onDropViewInstance(view)
    disposable?.let {
      if (!it.isDisposed) it.dispose()
    }
  }

  @ReactProp(name = "url")
  fun setUrl(view: TurboImageView, url: String) {
    view.setUrl(url)
  }

  @ReactProp(name = "resizeMode")
  fun setResizeMode(view: TurboImageView, resizeMode: String?) {
    view.scaleType = RESIZE_MODE[resizeMode]
  }

  @ReactProp(name = "base64Placeholder")
  fun setBase64Placeholder(view: TurboImageView, base64Placeholder: String?) {
    view.setBase64Placeholder(base64Placeholder)
  }

  @ReactProp(name = "fadeDuration")
  fun setCrossfade(view: TurboImageView, crossfade: Int = CrossfadeDrawable.DEFAULT_DURATION) {
    view.setCrossfade(crossfade)
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
