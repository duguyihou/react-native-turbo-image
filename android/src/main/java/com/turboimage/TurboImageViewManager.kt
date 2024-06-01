package com.turboimage

import android.os.Build.VERSION.SDK_INT
import android.widget.ImageView.ScaleType
import coil.decode.GifDecoder
import coil.decode.ImageDecoderDecoder
import coil.decode.SvgDecoder
import coil.dispose
import coil.drawable.CrossfadeDrawable
import coil.load
import coil.request.CachePolicy
import coil.size.Dimension
import coil.size.Size
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

class TurboImageViewManager : SimpleViewManager<TurboImageView>() {
  override fun getName() = REACT_CLASS

  override fun getExportedCustomBubblingEventTypeConstants(): Map<String, Any> {
    return mapOf(
      "onFailure" to mapOf(
        "phasedRegistrationNames" to mapOf(
          "bubbled" to "onFailure"
        )
      ),
      "onSuccess" to mapOf(
        "phasedRegistrationNames" to mapOf(
          "bubbled" to "onSuccess"
        )
      ),
      "onStart" to mapOf(
        "phasedRegistrationNames" to mapOf(
          "bubbled" to "onStart"
        )
      ),
      "onCompletion" to mapOf(
        "phasedRegistrationNames" to mapOf(
          "bubbled" to "onCompletion"
        )
      )
    )
  }

  override fun createViewInstance(reactContext: ThemedReactContext): TurboImageView {
    return TurboImageView(reactContext)
  }

  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)

    view.load(view.src) {
      listener(TurboImageListener(view))
      diskCachePolicy(
        if (view.cachePolicy != "memory")
          CachePolicy.ENABLED
        else
          CachePolicy.DISABLED
      )
      view.isSVG?.let {
        decoderFactory { result, options, _ ->
          SvgDecoder(result.source, options)
        }
      }
      view.isGif?.let {
        decoderFactory { result, options, _ ->
          if (SDK_INT >= 28) {
            ImageDecoderDecoder(result.source, options)
          } else {
            GifDecoder(result.source, options)
          }
        }
      }
      placeholder(view.blurHashDrawable ?: view.circleProgressDrawable)
      transformations(view.transformations)
      crossfade(view.crossfade ?: CrossfadeDrawable.DEFAULT_DURATION)
      error(view.blurHashDrawable)
      size(view.resize ?: Size.ORIGINAL)
    }
  }

  override fun onDropViewInstance(view: TurboImageView) {
    super.onDropViewInstance(view)
    view.dispose()
  }

  @ReactProp(name = "src")
  fun setSrc(view: TurboImageView, src: String) {
    view.src = src
  }

  @ReactProp(name = "blurhash")
  fun setBlurHash(view: TurboImageView, blurhash: String?) {
    view.blurHash = blurhash
  }

  @ReactProp(name = "cachePolicy")
  fun setCachePolicy(view: TurboImageView, cachePolicy: String?) {
    view.cachePolicy = cachePolicy
  }

  @ReactProp(name = "resizeMode")
  fun setResizeMode(view: TurboImageView, resizeMode: String?) {
    view.scaleType = RESIZE_MODE[resizeMode]
  }

  @ReactProp(name = "indicator")
  fun setIndicator(view: TurboImageView, indicator: String?) {
    view.indicator = indicator
  }

  @ReactProp(name = "fadeDuration")
  fun setCrossfade(view: TurboImageView, crossfade: Int?) {
    view.crossfade = crossfade
  }

  @ReactProp(name = "borderRadius")
  fun setBorderRadius(view: TurboImageView, borderRadius: Int?) {
    view.borderRadius = borderRadius
  }

  @ReactProp(name = "rounded")
  fun setRounded(view: TurboImageView, rounded: Boolean?) {
    view.rounded = rounded
  }

  @ReactProp(name = "blur")
  fun setBlur(view: TurboImageView, blur: Int?) {
    view.blur = blur
  }

  @ReactProp(name = "monochrome")
  fun setMonochrome(view: TurboImageView, monochrome: Int?) {
    view.monochrome = monochrome
  }

  @ReactProp(name = "resize")
  fun setResize(view: TurboImageView, resize: Int?) {
    resize?.let {
      view.resize = Size(
        PixelUtil.toPixelFromDIP(resize.toFloat()).toInt(),
        Dimension.Undefined
      )
    }
  }

  @ReactProp(name = "tint")
  fun setTint(view: TurboImageView, tint: Int?) {
    view.tint = tint
  }

  @ReactProp(name = "isSVG")
  fun setIsSVG(view: TurboImageView, isSVG: Boolean?) {
    view.isSVG = isSVG
  }

  @ReactProp(name = "isGif")
  fun setIsGif(view: TurboImageView, isGif: Boolean?) {
    view.isGif = isGif
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
