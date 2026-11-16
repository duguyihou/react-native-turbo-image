package com.turboimage

import android.annotation.SuppressLint
import android.graphics.Bitmap
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
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

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

  // Placeholder hashes. A change re-decodes; see [applyPlaceholder].
  var blurhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  var thumbhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }

  private var needsReload = false
  private var needsPlaceholder = false
  private var handle: LoadHandle? = null
  // Mirrors the iOS view: once the loaded image is shown, a late placeholder
  // must not replace it, and a newer decode supersedes an older one.
  private var showingFinalImage = false
  private var placeholderGeneration = 0

  init {
    scaleType = ScaleType.CENTER_CROP
    // `cover` scales past the view's bounds by design, and ImageView only
    // clips that if its parent does. Fabric's ReactViewGroup sets
    // clipChildren=false (to support overflow: visible), so without this an
    // image whose aspect differs from the view paints over its neighbours.
    // Mirrors `clipsToBounds = YES` on iOS.
    cropToPadding = true
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

  /** Called once per Fabric transaction, after all props have landed. */
  fun onTransactionEnd() {
    if (needsReload) {
      // reload clears the view, so the placeholder must be (re)applied.
      needsPlaceholder = true
      maybeReload()
    }
    if (needsPlaceholder) {
      needsPlaceholder = false
      applyPlaceholder()
    }
  }

  private fun applyPlaceholder() {
    val generation = ++placeholderGeneration
    if (showingFinalImage) return
    // Snapshot: props may change before the decode runs.
    val blur = blurhash.orEmpty()
    val thumb = thumbhash.orEmpty()
    if (blur.isEmpty() && thumb.isEmpty()) return

    placeholderExecutor.execute {
      val pixels = TurboImageCore.decodePlaceholder(blur, thumb) ?: return@execute
      val bitmap =
        Bitmap.createBitmap(pixels.width, pixels.height, Bitmap.Config.ARGB_8888).apply {
          // The core returns premultiplied RGBA, ARGB_8888's in-memory layout.
          copyPixelsFromBuffer(ByteBuffer.wrap(pixels.rgba))
        }
      post {
        if (generation == placeholderGeneration && !showingFinalImage) {
          setImageBitmap(bitmap)
        }
      }
    }
  }

  private fun maybeReload() {
    if (!needsReload) return
    needsReload = false
    cancel()
    setImageDrawable(null)
    showingFinalImage = false

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
            showingFinalImage = true
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
    ++placeholderGeneration // drop any decode still in flight
  }

  private fun emitError(code: Int, message: String) =
    dispatch(ErrorEvent(surfaceId(), id, TurboImageCore.loadErrorCodeName(code), message))

  private fun surfaceId() = UIManagerHelper.getSurfaceId(this)

  private fun dispatch(event: Event<*>) {
    UIManagerHelper.getEventDispatcher(reactContext)?.dispatchEvent(event)
  }

  private companion object {
    // One background thread is plenty: a decode is ~1 ms, and serialising
    // them bounds memory when a list mounts many placeholders at once.
    val placeholderExecutor: ExecutorService =
      Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "TurboImagePlaceholder").apply { isDaemon = true }
      }
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
