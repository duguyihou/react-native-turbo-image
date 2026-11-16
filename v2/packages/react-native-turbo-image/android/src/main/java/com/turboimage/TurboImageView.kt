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
  private var progressThrottle = TurboImageCore.ProgressThrottle()

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
    // A load still in flight is superseded: tell JS it was cancelled, so
    // every onStart is matched by exactly one onCompletion (as on iOS).
    if (handle != null) {
      cancel()
      emitCompletion("cancelled")
    } else {
      cancel()
    }
    setImageDrawable(null)
    showingFinalImage = false
    progressThrottle = TurboImageCore.ProgressThrottle()

    // Requests the core rejects fail before onStart: no load ever began.
    val invalid = TurboImageCore.LoadErrorCode.INVALID_REQUEST.nativeValue
    val result =
      uri?.let { TurboImageCore.resolve(it, cacheKey, cachePolicy) }
        ?: ResolveFailure(errorCode = 1) // EmptyUri, same as the core's code
    when (result) {
      is ResolveFailure -> {
        emitFailure(invalid, "Invalid request (core error ${result.errorCode})")
        emitCompletion("completed")
      }
      is ResolvedRequest -> startLoad(result)
    }
  }

  private fun startLoad(request: ResolvedRequest) {
    emit("topStart") { putString("state", "running") }

    // Capture the handle identity so a late callback from a replaced load
    // cannot touch this view (same guard as the iOS view).
    var thisHandle: LoadHandle? = null
    thisHandle =
      loader.load(
        this as ImageView,
        request,
        object : ImageLoaderAdapter.Listener {
          override fun onProgress(completed: Long, total: Long) {
            if (handle !== thisHandle || !progressThrottle.shouldReport(completed, total)) return
            emit("topProgress") {
              putDouble("completed", completed.toDouble())
              putDouble("total", if (total > 0) total.toDouble() else -1.0)
            }
          }

          override fun onSuccess(width: Int, height: Int) {
            if (handle !== thisHandle) return
            handle = null
            showingFinalImage = true
            emit("topSuccess") {
              putDouble("width", width.toDouble())
              putDouble("height", height.toDouble())
              putString("source", request.url)
            }
            emitCompletion("completed")
          }

          override fun onError(code: Int, message: String) {
            if (handle !== thisHandle) return
            handle = null
            emitFailure(code, message)
            emitCompletion("completed")
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

  private fun emitFailure(code: Int, message: String) =
    emit("topFailure") {
      putString("code", TurboImageCore.loadErrorCodeName(code))
      putString("error", message)
    }

  private fun emitCompletion(state: String) = emit("topCompletion") { putString("state", state) }

  private fun emit(name: String, payload: WritableMap.() -> Unit) {
    val event = TurboImageEvent(UIManagerHelper.getSurfaceId(this), id, name, Arguments.createMap().apply(payload))
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

  // One event class for all five events; they differ only in name and
  // payload. Coalescing is off: RN's default would merge same-name events in
  // one batch, which must never drop an onStart/onCompletion pair.
  private class TurboImageEvent(
    surfaceId: Int,
    viewTag: Int,
    private val name: String,
    private val payload: WritableMap,
  ) : Event<TurboImageEvent>(surfaceId, viewTag) {
    override fun getEventName() = name

    override fun canCoalesce() = false

    override fun getEventData(): WritableMap = payload
  }
}
