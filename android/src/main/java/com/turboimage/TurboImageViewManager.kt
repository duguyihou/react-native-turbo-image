package com.turboimage

import android.graphics.drawable.BitmapDrawable
import android.os.Build.VERSION.SDK_INT
import android.widget.ImageView.ScaleType
import coil.Coil
import coil.decode.GifDecoder
import coil.decode.ImageDecoderDecoder
import coil.decode.SvgDecoder
import coil.dispose
import coil.drawable.CrossfadeDrawable
import coil.load
import coil.memory.MemoryCache
import coil.size.Dimension
import coil.size.Size
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.annotations.ReactProp
import java.util.Collections
import java.util.WeakHashMap
import okhttp3.Headers
import com.turboimage.decoder.APNGDecoder
import com.turboimage.events.ProgressEvent
import com.turboimage.events.interceptor.ProgressInterceptor
import com.turboimage.events.interceptor.ProgressListener
import okhttp3.OkHttpClient
import androidx.core.graphics.drawable.toDrawable

class TurboImageViewManager : SimpleViewManager<TurboImageView>(), LifecycleEventListener {
  override fun getName() = REACT_CLASS

  private val attachedViews =
    Collections.newSetFromMap(WeakHashMap<TurboImageView, Boolean>())
  private var isInBackground = false
  override fun getExportedCustomDirectEventTypeConstants(): MutableMap<String, Any>? {
    return MapBuilder.of(
      "onStart", MapBuilder.of("registrationName", "onStart"),
      "onProgress", MapBuilder.of("registrationName", "onProgress"),
      "onSuccess", MapBuilder.of("registrationName", "onSuccess"),
      "onFailure", MapBuilder.of("registrationName", "onFailure"),
      "onCompletion", MapBuilder.of("registrationName", "onCompletion"),
    )
  }

  override fun createViewInstance(reactContext: ThemedReactContext): TurboImageView {
    reactContext.addLifecycleEventListener(this)
    return TurboImageView(reactContext).also { attachedViews.add(it) }
  }

  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    reloadImage(view)
  }

  override fun onDropViewInstance(view: TurboImageView) {
    super.onDropViewInstance(view)
    view.dispose()
    attachedViews.remove(view)
  }

  private fun reloadImage(view: TurboImageView) {
    val defaultCrossfade = if (view.thumbhashDrawable != null || view.blurhashDrawable != null) {
      0
    } else {
      CrossfadeDrawable.DEFAULT_DURATION
    }

    val okHttpClient = OkHttpClient.Builder()
      .addInterceptor(ProgressInterceptor(object : ProgressListener {
        override fun update(bytesRead: Long, contentLength: Long, done: Boolean) {
          val reactContext = view.context as ReactContext
          UIManagerHelper.getEventDispatcher(reactContext, view.id)?.let {
            val payload = Arguments.createMap().apply {
              putDouble("completed", bytesRead.toDouble())
              putDouble("total", contentLength.toDouble())
            }
            val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
            it.dispatchEvent(ProgressEvent(surfaceId, view.id, payload))
          }
        }
      }))
      .build()

    val imageLoader = Coil.imageLoader(view.context).newBuilder()
      .respectCacheHeaders(view.cachePolicy == "urlCache")
      .okHttpClient(okHttpClient)
      .build()

    view.load(view.uri, imageLoader) {
      view.headers?.let { headers(it) }
      view.cacheKey?.let {
        memoryCacheKey(it)
        diskCacheKey(it)
      }
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
      view.memoryCacheKey?.let {
        placeholderMemoryCacheKey(it)
      }
      transformations(view.transformations)
      crossfade(view.crossfade ?: defaultCrossfade)
      view.showPlaceholderOnFailure?.let {
        if (view.memoryCacheKey != null) {
          imageLoader.memoryCache?.get(MemoryCache.Key(view.memoryCacheKey!!))?.let { value ->
            error(value.bitmap.toDrawable(view.context.resources))
          }
        } else {
          error(view.thumbhashDrawable ?: view.blurhashDrawable)
        }
      }
      view.resize?.let { size(it) }
    }
  }

  @ReactProp(name = "source")
  fun setSource(view: TurboImageView, source: ReadableMap) {
    val uri = source.toHashMap()["uri"] as? String
    view.uri = uri
    val headers = source.toHashMap()["headers"] as? HashMap<*, *>
    val headersBuilder = Headers.Builder()
    headers?.map { (key, value) ->
      headersBuilder.add(key as String, value as String)
    }
    view.headers = headersBuilder.build()
    view.cacheKey = source.toHashMap()["cacheKey"] as? String
  }

  @ReactProp(name = "placeholder")
  fun setPlaceholder(view: TurboImageView, placeholder: ReadableMap?) {
    view.blurhash = placeholder?.getString("blurhash")
    view.thumbhash = placeholder?.getString("thumbhash")
    view.memoryCacheKey = placeholder?.getString("memoryCacheKey")
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

  override fun onHostResume() {
    if (isInBackground) {
      attachedViews.toList().forEach { reloadImage(it) }
      isInBackground = false
    }
  }

  override fun onHostPause() {
    attachedViews.toList().forEach { it.dispose() }
    isInBackground = true
  }

  override fun onHostDestroy() {
    attachedViews.toList().forEach { it.dispose() }
    attachedViews.clear()
  }
}
