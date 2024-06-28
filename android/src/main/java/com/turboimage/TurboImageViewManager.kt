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
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import okhttp3.Headers
import com.turboimage.decoder.APNGDecoder

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

    view.load(view.uri) {
      view.headers?.let { headers(it) }
      listener(TurboImageListener(view))
      diskCachePolicy(
        if (view.cachePolicy != "memory")
          CachePolicy.ENABLED
        else
          CachePolicy.DISABLED
      )
      view.format?.let {
        when (it) {
          "svg" -> {
            decoderFactory { result, options, _ ->
              SvgDecoder(result.source, options)
            }
          }

          "gif" -> {
            decoderFactory { result, options, _ ->
              if (SDK_INT >= 28) {
                ImageDecoderDecoder(result.source, options)
              } else {
                GifDecoder(result.source, options)
              }
            }
          }

          else -> {}
        }
      }
      view.isAPNG?.let {
        decoderFactory { result, _, _ ->
          APNGDecoder(result.source)
        }
      }

      placeholder(
        view.thumbhashDrawable
          ?: view.blurhashDrawable
          ?: view.circleProgressDrawable
      )
      transformations(view.transformations)
      crossfade(view.crossfade ?: CrossfadeDrawable.DEFAULT_DURATION)
      error(view.blurhashDrawable)
      size(view.resize ?: Size.ORIGINAL)
    }
  }

  override fun onDropViewInstance(view: TurboImageView) {
    super.onDropViewInstance(view)
    view.dispose()
  }

  @ReactProp(name = "source")
  fun setSource(view: TurboImageView, source: ReadableMap) {
    view.uri = source.toHashMap()["uri"] as? String
    view.headers = source.toHashMap()["headers"] as? Headers
  }

  @ReactProp(name = "placeholder")
  fun setPlaceholder(view: TurboImageView, placeholder: ReadableMap?) {
    view.blurhash = placeholder?.getString("blurhash")
    view.thumbhash = placeholder?.getString("thumbhash")
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
  fun setIndicator(view: TurboImageView, indicator: ReadableMap?) {
    indicator?.let {
      if (it.hasKey("style")) {
        view.indicator["style"] = it.getString("style") ?: "medium"
      } else {
        view.indicator["style"] = "medium"
      }
      if (it.hasKey("color")) {
        view.indicator["color"] = it.getInt("color")
      }
    }
  }

  @ReactProp(name = "fadeDuration")
  fun setCrossfade(view: TurboImageView, crossfade: Int?) {
    view.crossfade = crossfade
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

  @ReactProp(name = "format")
  fun setFormat(view: TurboImageView, format: String?) {
    view.format = format
  }

  @ReactProp(name = "isAPNG")
  fun setIsAPNG(view: TurboImageView, isAPNG: Boolean?) {
    view.isAPNG = isAPNG
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
