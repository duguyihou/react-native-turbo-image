package com.turboimage

import android.annotation.SuppressLint
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import com.turboimage.core.ResolveFailure
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import com.turboimage.loader.ImageLoaderAdapter
import com.turboimage.loader.LoadHandle

/**
 * Fabric host view for <TurboImage> on Android. Mirrors
 * ios/Fabric/TurboImageComponentView.mm step for step:
 * props → C++ core → loader adapter → display + events.
 */
@SuppressLint("ViewConstructor")
class TurboImageView(
  private val reactContext: ThemedReactContext,
  private val loader: ImageLoaderAdapter,
) : AppCompatImageView(reactContext) {

  // Request-defining props. A change to any of them marks the view dirty;
  // the load itself starts once per transaction in [maybeReload].
  var uri: String? = null
    set(value) { if (field != value) { field = value; needsReload = true } }
  var cacheKey: String? = null
    set(value) { if (field != value) { field = value; needsReload = true } }
  var cachePolicy: TurboImageCore.CachePolicy = TurboImageCore.CachePolicy.DEFAULT
    set(value) { if (field != value) { field = value; needsReload = true } }

  private var needsReload = false
  private var handle: LoadHandle? = null

  init {
    scaleType = ScaleType.CENTER_CROP
  }

  fun setResizeMode(mode: String?) {
    scaleType =
      when (mode) {
        "contain" -> ScaleType.FIT_CENTER
        "stretch" -> ScaleType.FIT_XY
        "center" -> ScaleType.CENTER
        else -> ScaleType.CENTER_CROP
      }
  }

  fun maybeReload() {
    if (!needsReload) return
    needsReload = false
    cancel()
    setImageDrawable(null)

    val invalid = TurboImageCore.LoadErrorCode.INVALID_REQUEST.nativeValue
    val source = uri ?: return emitError(invalid, "Missing source.uri")
    when (val result = TurboImageCore.resolve(source, cacheKey, cachePolicy)) {
      is ResolveFailure -> emitError(invalid, "Invalid request (core error ${result.errorCode})")
      is ResolvedRequest -> startLoad(result)
    }
  }

  private fun startLoad(request: ResolvedRequest) {
    // Capture the handle identity so a late callback from a replaced load
    // cannot touch this view (same guard as the iOS view).
    var thisHandle: LoadHandle? = null
    thisHandle =
      loader.load(
        this as ImageView,
        request,
        object : ImageLoaderAdapter.Listener {
          override fun onSuccess(width: Int, height: Int) {
            if (handle !== thisHandle) return
            handle = null
            dispatch(LoadEvent(surfaceId(), id, width.toDouble(), height.toDouble()))
          }

          override fun onError(code: Int, message: String) {
            if (handle !== thisHandle) return
            handle = null
            emitError(code, message)
          }
        },
      )
    handle = thisHandle
  }

  fun cancel() {
    handle?.cancel()
    handle = null
  }

  private fun emitError(code: Int, message: String) =
    dispatch(ErrorEvent(surfaceId(), id, TurboImageCore.loadErrorCodeName(code), message))

  private fun surfaceId() = UIManagerHelper.getSurfaceId(this)

  private fun dispatch(event: Event<*>) {
    UIManagerHelper.getEventDispatcher(reactContext)?.dispatchEvent(event)
  }

  private class LoadEvent(surfaceId: Int, viewTag: Int, val width: Double, val height: Double) :
    Event<LoadEvent>(surfaceId, viewTag) {
    override fun getEventName() = "topLoad"

    override fun getEventData(): WritableMap =
      Arguments.createMap().apply {
        putDouble("width", width)
        putDouble("height", height)
      }
  }

  private class ErrorEvent(surfaceId: Int, viewTag: Int, val code: String, val message: String) :
    Event<ErrorEvent>(surfaceId, viewTag) {
    override fun getEventName() = "topError"

    override fun getEventData(): WritableMap =
      Arguments.createMap().apply {
        putString("code", code)
        putString("message", message)
      }
  }
}
