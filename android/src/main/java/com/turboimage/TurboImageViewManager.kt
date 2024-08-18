package com.turboimage

import android.content.ContentResolver
import android.net.Uri
import android.os.Build.VERSION.SDK_INT
import android.widget.ImageView.ScaleType
import coil.Coil
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
import com.facebook.react.views.imagehelper.ResourceDrawableIdHelper
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
      ), "onSuccess" to mapOf(
        "phasedRegistrationNames" to mapOf(
          "bubbled" to "onSuccess"
        )
      ), "onStart" to mapOf(
        "phasedRegistrationNames" to mapOf(
          "bubbled" to "onStart"
        )
      ), "onCompletion" to mapOf(
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
    val defaultCrossfade = if (view.thumbhashDrawable != null || view.blurhashDrawable != null) {
      0
    } else {
      CrossfadeDrawable.DEFAULT_DURATION
    }

    val imageLoader = Coil.imageLoader(view.context).newBuilder()
      .respectCacheHeaders(view.cachePolicy == "urlCache").build()

    view.load(view.uri, imageLoader) {
      view.headers?.let { headers(it) }
      view.allowHardware?.let { allowHardware(it) }
      listener(TurboImageListener(view))
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

          "apng" -> {
            decoderFactory { result, _, _ ->
              APNGDecoder(result.source)
            }
          }

          else -> {}
        }
      }

      placeholder(
        view.thumbhashDrawable ?: view.blurhashDrawable ?: view.circleProgressDrawable
      )
      transformations(view.transformations)
      crossfade(view.crossfade ?: defaultCrossfade)
      view.showPlaceholderOnFailure?.let {
        error(view.thumbhashDrawable ?: view.blurhashDrawable)
      }
      size(view.resize ?: Size.ORIGINAL)
    }
  }

  override fun onDropViewInstance(view: TurboImageView) {
    super.onDropViewInstance(view)
    view.dispose()
  }

  @ReactProp(name = "source")
  fun setSource(view: TurboImageView, source: ReadableMap) {
    val uri = source.toHashMap()["uri"] as? String
    if (source.hasKey("__packager_asset") && uri?.startsWith("http") == false) {
      val resId = ResourceDrawableIdHelper.getInstance().getResourceDrawableId(view.context, uri)
      val url = Uri.Builder().scheme(ContentResolver.SCHEME_ANDROID_RESOURCE)
        .authority(view.context.resources.getResourcePackageName(resId))
        .appendPath(view.context.resources.getResourceTypeName(resId))
        .appendPath(view.context.resources.getResourceEntryName(resId)).build()
      view.uri = url.toString()
    } else {
      view.uri = uri
      view.headers = source.toHashMap()["headers"] as? Headers
    }
  }

  @ReactProp(name = "placeholder")
  fun setPlaceholder(view: TurboImageView, placeholder: ReadableMap?) {
    view.blurhash = placeholder?.getString("blurhash")
    view.thumbhash = placeholder?.getString("thumbhash")
  }

  @ReactProp(name = "showPlaceholderOnFailure")
  fun setShowPlaceholderOnFailure(view: TurboImageView, showPlaceholderOnFailure: Boolean?) {
    view.showPlaceholderOnFailure = showPlaceholderOnFailure
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
        PixelUtil.toPixelFromDIP(resize.toFloat()).toInt(), Dimension.Undefined
      )
    }
  }

  @ReactProp(name = "tint")
  fun setTint(view: TurboImageView, tint: Int?) {
    view.tint = tint
  }

  @ReactProp(name = "allowHardware")
  fun setAllowHardware(view: TurboImageView, allowHardware: Boolean?) {
    view.allowHardware = allowHardware
  }

  @ReactProp(name = "format")
  fun setFormat(view: TurboImageView, format: String?) {
    view.format = format
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
