package com.turboimage

import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.widget.ImageView.ScaleType
import coil.Coil
import coil.Coil.imageLoader
import coil.ImageLoader
import coil.request.CachePolicy
import coil.request.Disposable
import coil.request.ImageRequest
import coil.transform.CircleCropTransformation
import coil.transform.RoundedCornersTransformation
import com.commit451.coiltransformations.BlurTransformation
import com.commit451.coiltransformations.GrayscaleTransformation
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.uimanager.PixelUtil
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.uimanager.events.RCTEventEmitter

class TurboImageViewManager : SimpleViewManager<TurboImageView>() {
  override fun getName() = REACT_CLASS
  private var disposable: Disposable? = null

  override fun getExportedCustomBubblingEventTypeConstants(): Map<String, Any> {
    return mapOf(
      "onFailure" to mapOf(
        "phasedRegistrationNames" to mapOf(
          "bubbled" to "onError"
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
      )
    )
  }

  override fun createViewInstance(reactConText: ThemedReactContext): TurboImageView {
    return TurboImageView(reactConText)
  }

  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)

    // TODO: refactor it
    val imageLoader = ImageLoader.Builder(view.context)
      .respectCacheHeaders(view.cachePolicy == "urlCache")
      .build()
    Coil.setImageLoader(imageLoader)

    val blurHashDrawable = view.blurhash?.let { drawBlurHash(view, it) }
    val diskCacheEnabled =
      if (view.cachePolicy != "memory") CachePolicy.ENABLED else CachePolicy.DISABLED
    val request = ImageRequest.Builder(view.context)
      .data(view.src)
      .target(view)
      .listener(
        onStart = { _ ->
          val payload = WritableNativeMap().apply {
            putString("state", "running")
          }
          val reactContext = view.context as ReactContext
          reactContext.getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(view.id, "onStart", payload)
        },
        onSuccess = { request, result ->
          val payload = WritableNativeMap().apply {
            putInt("width", result.drawable.intrinsicWidth)
            putInt("height", result.drawable.intrinsicHeight)
            putString("source", request.data.toString())
          }
          val reactContext = view.context as ReactContext
          reactContext.getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(view.id, "onSuccess", payload)
        },
        onError = { _, result ->
          val payload = WritableNativeMap().apply {
            putString("error", result.throwable.cause?.localizedMessage)
          }
          val reactContext = view.context as ReactContext
          reactContext.getJSModule(RCTEventEmitter::class.java)
            .receiveEvent(view.id, "onFailure", payload)
        }
      )
      .memoryCachePolicy(CachePolicy.ENABLED)
      .diskCachePolicy(diskCacheEnabled)
      .placeholder(blurHashDrawable)
      .transformations(view.transformations)
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

  @ReactProp(name = "src")
  fun setSrc(view: TurboImageView, src: String) {
    view.src = src
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
      val borderRadii = PixelUtil.toPixelFromDIP(borderRadius.toFloat())
      val roundedCornersTransformation = RoundedCornersTransformation(borderRadii)
      view.transformations.add(roundedCornersTransformation)
    }
  }

  @ReactProp(name = "rounded")
  fun setRounded(view: TurboImageView, rounded: Boolean?) {
    rounded?.let {
      val circleCropTransformation = CircleCropTransformation()
      view.transformations.add(circleCropTransformation)
    }
  }

  @ReactProp(name = "blur")
  fun setBlur(view: TurboImageView, blur: Int?) {
    blur?.let {
      val blurTransformation = BlurTransformation(view.context, blur.toFloat())
      view.transformations.add(blurTransformation)
    }
  }

  // TODO: custom color, not grayscale
  @ReactProp(name = "monochrome")
  fun setMonochrome(view: TurboImageView, monochrome: Int?) {
    monochrome?.let {
      val grayscaleTransformation = GrayscaleTransformation()
      view.transformations.add(grayscaleTransformation)
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
