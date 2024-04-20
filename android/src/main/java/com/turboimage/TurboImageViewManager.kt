package com.turboimage

import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.widget.ImageView.ScaleType
import coil.Coil.imageLoader
import coil.request.CachePolicy
import coil.request.Disposable
import coil.request.ImageRequest
import coil.transform.RoundedCornersTransformation
import coil.transform.Transformation
import com.commit451.coiltransformations.ColorFilterTransformation
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class TurboImageViewManager : SimpleViewManager<TurboImageView>() {
  override fun getName() = REACT_CLASS
  private var disposable: Disposable? = null
  private val transformations: MutableList<Transformation> = mutableListOf()
  override fun createViewInstance(reactConText: ThemedReactContext): TurboImageView {
    return  TurboImageView(reactConText)
  }

  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    val blurHashDrawable = view.blurhash?.let { drawBlurHash(view, it) }
    val request = ImageRequest.Builder(view.context)
      .data(view.url)
      .target(view)
      .memoryCachePolicy(if (view.cachePolicy == "memory") CachePolicy.ENABLED else CachePolicy.DISABLED)
      .diskCachePolicy(if (view.cachePolicy != "memory") CachePolicy.ENABLED else CachePolicy.DISABLED)
      .placeholder(blurHashDrawable)
      .transformations(transformations)
      .crossfade(view.crossfade)
      .build()
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

  @ReactProp(name = "blurhash")
  fun setBlurHash(view: TurboImageView, blurhash: String?) {
    view.blurhash = blurhash
  }

  @ReactProp(name = "borderRadius")
  fun setBorderRadius(view: TurboImageView, borderRadius: Int?) {
    borderRadius?.let {
      val  roundedCornersTransformation = RoundedCornersTransformation(borderRadius.toFloat())
      transformations.add(roundedCornersTransformation)
    }

  }

  private fun drawBlurHash(view: TurboImageView, blurHash: String): Drawable {
    val bitmap = BlurHashDecoder.decode(blurHash, 8, 8)
    return BitmapDrawable(view.context.resources, bitmap)
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
