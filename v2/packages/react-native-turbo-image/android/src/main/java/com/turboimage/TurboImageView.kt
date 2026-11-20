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
  var headers: List<Pair<String, String>> = emptyList()
    set(value) { if (field != value) { field = value; needsReload = true } }
  var cachePolicy: TurboImageCore.CachePolicy = TurboImageCore.CachePolicy.DEFAULT
    set(value) { if (field != value) { field = value; needsReload = true } }
  // Processors change the pixels, so they need a new load (served from the
  // disk original, or memory if this variant is cached). Same rule as iOS.
  var processing = TurboImageCore.Processing()
    set(value) { if (field != value) { field = value; needsReload = true } }

  // Placeholder hashes. A change re-decodes; see [applyPlaceholder].
  var blurhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  var thumbhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  var memoryCacheKey: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }

  // Not a request prop: a new key alone starts no load, because the image on
  // screen is still the one `uri` names. It only decides how the load started
  // in this same transaction treats the previous image (see [maybeReload]).
  var recyclingKey: String? = null
    set(value) { if (field != value) { field = value; recyclingKeyChanged = true } }

  private var needsReload = false
  private var needsPlaceholder = false
  private var recyclingKeyChanged = false
  // The image of the previous request is still on screen while the current
  // load runs. It stands in for the placeholder, so no placeholder may
  // replace it (same rule as the iOS view).
  private var showingPreviousImage = false
  // The load in flight, if any: a token made before the adapter is called,
  // null again once the load succeeds, fails or is cancelled. A callback acts
  // only while its own token is still here.
  //
  // Not the adapter's [LoadHandle]: a memory-cache hit calls back inside
  // `loader.load()`, before that handle exists. Comparing handles let such a
  // callback through (both sides null) and then stored a handle for a load
  // that had already finished, so the next reload reported a second,
  // "cancelled" onCompletion for it.
  private var inFlight: Any? = null
  // Cancels [inFlight]; null when nothing is in flight.
  private var handle: LoadHandle? = null
  // Mirrors the iOS view: once the loaded image is shown, a late placeholder
  // must not replace it, and a newer decode supersedes an older one.
  private var showingFinalImage = false
  // The current load failed; with showPlaceholderOnFailure=false no
  // placeholder may appear any more (same rule as the iOS view).
  private var loadFailed = false
  private var placeholderGeneration = 0
  private var progressThrottle = TurboImageCore.ProgressThrottle()
  // Last Content-Length seen this load, for the throttle's finish() step.
  private var lastProgressTotal = -1L

  /** 1.x semantics: false removes the placeholder when the load fails. */
  var showPlaceholderOnFailure = false

  /** Cross-fade duration in ms; 0 disables it. 1.x default. */
  var fadeDuration = 300

  /** 1.x prop: false decodes to a software bitmap. Changing it reloads. */
  var allowHardware = true
    set(value) { if (field != value) { field = value; needsReload = true } }

  /**
   * false decodes the original instead of the view's size. Changing it
   * reloads, because the image on screen was decoded for the other answer.
   */
  var allowDownscaling = true
    set(value) { if (field != value) { field = value; needsReload = true } }

  // A request prop as well as a drawing one: `contain` needs fewer pixels
  // than `cover`, and `center` needs them all (the core's decode-size rule),
  // so an image decoded for one mode can be too small for another.
  private var resizeMode = TurboImageCore.ResizeMode.CONTAIN
    set(value) { if (field != value) { field = value; needsReload = true } }

  init {
    // Matches the spec default (`contain`, 1.x's default).
    scaleType = ScaleType.FIT_CENTER
    // `cover` scales past the view's bounds by design, and ImageView only
    // clips that if its parent does. Fabric's ReactViewGroup sets
    // clipChildren=false (to support overflow: visible), so without this an
    // image whose aspect differs from the view paints over its neighbours.
    // Mirrors `clipsToBounds = YES` on iOS.
    cropToPadding = true
  }

  fun setResizeMode(mode: String?) {
    val (scale, core) =
      when (mode) {
        "cover" -> ScaleType.CENTER_CROP to TurboImageCore.ResizeMode.COVER
        "stretch" -> ScaleType.FIT_XY to TurboImageCore.ResizeMode.STRETCH
        "center" -> ScaleType.CENTER to TurboImageCore.ResizeMode.CENTER
        else -> ScaleType.FIT_CENTER to TurboImageCore.ResizeMode.CONTAIN // the default
      }
    scaleType = scale
    resizeMode = core
  }


  /** Called once per Fabric transaction, after all props have landed. */
  fun onTransactionEnd() {
    if (needsReload) {
      // reload may clear the view, so the placeholder must be (re)applied.
      needsPlaceholder = true
      maybeReload()
    }
    // Consumed by the load above, or dropped: the key applies only to a load
    // in its own transaction.
    recyclingKeyChanged = false
    if (needsPlaceholder) {
      needsPlaceholder = false
      applyPlaceholder()
    }
  }

  private fun applyPlaceholder() {
    val generation = ++placeholderGeneration
    if (!placeholderAllowed()) return
    // memoryCacheKey: a synchronous memory-cache lookup (no decode, no
    // disk). The core says which keys the prop may name (an explicit
    // cacheKey as written, or a URI's canonical form); the first hit wins.
    memoryCacheKey?.takeIf { it.isNotEmpty() }?.let { key ->
      // A miss clears the view, for the same reason as "no placeholder"
      // below: what it shows is the placeholder of earlier props. (JS allows
      // one placeholder kind at a time, so there is no hash to fall back on.)
      setImageDrawable(
        TurboImageCore.memoryCacheKeyCandidates(key)
          .firstNotNullOfOrNull { loader.memoryCachedDrawable(it, resources) })
      return
    }

    // Snapshot: props may change before the decode runs.
    val blur = blurhash.orEmpty()
    val thumb = thumbhash.orEmpty()
    if (blur.isEmpty() && thumb.isEmpty()) {
      // No placeholder is asked for (any more). [placeholderAllowed] says the
      // view holds no loaded image, so whatever it shows is a placeholder the
      // props have since dropped: remove it, rather than leave it up until
      // the load ends. Same rule as the iOS view.
      setImageDrawable(null)
      return
    }

    placeholderExecutor.execute {
      val pixels = TurboImageCore.decodePlaceholder(blur, thumb) ?: return@execute
      val bitmap =
        Bitmap.createBitmap(pixels.width, pixels.height, Bitmap.Config.ARGB_8888).apply {
          // The core returns premultiplied RGBA, ARGB_8888's in-memory layout.
          copyPixelsFromBuffer(ByteBuffer.wrap(pixels.rgba))
        }
      post {
        if (generation == placeholderGeneration && placeholderAllowed()) {
          setImageBitmap(bitmap)
        }
      }
    }
  }

  private fun placeholderAllowed() =
    !showingFinalImage && !showingPreviousImage && !(loadFailed && !showPlaceholderOnFailure)

  private fun onLoadFailed() {
    loadFailed = true
    // A previous image kept during the load goes either way: it is not what
    // `uri` names, and leaving it up would hide the failure.
    val hadPreviousImage = showingPreviousImage
    showingPreviousImage = false
    if (!showPlaceholderOnFailure) {
      ++placeholderGeneration // a decode still in flight must not appear
      setImageDrawable(null)
    } else if (hadPreviousImage) {
      // The placeholder was held back while the previous image stood in.
      setImageDrawable(null)
      applyPlaceholder()
    }
  }

  private fun maybeReload() {
    if (!needsReload) return
    needsReload = false
    // A load still in flight is superseded: tell JS it was cancelled, so
    // every onStart is matched by exactly one onCompletion (as on iOS).
    val superseded = inFlight != null
    cancel()
    if (superseded) emitCompletion("cancelled")
    // What stays on screen while this load runs (expo-image's rule):
    //   * same `recyclingKey`: the previous image, so a changed source or
    //     processor swaps (and cross-fades) without a blank frame in between;
    //   * new `recyclingKey`: nothing, or the placeholder. The view is being
    //     reused for other content, and the old image would be wrong.
    // Only a loaded image is kept, never a placeholder or a failed view.
    showingPreviousImage =
      (showingFinalImage || showingPreviousImage) && !recyclingKeyChanged && drawable != null
    if (!showingPreviousImage) {
      setImageDrawable(null)
    }
    showingFinalImage = false
    loadFailed = false
    progressThrottle = TurboImageCore.ProgressThrottle()
    lastProgressTotal = -1L

    // Requests the core rejects fail before onStart: no load ever began.
    val invalid = TurboImageCore.LoadErrorCode.INVALID_REQUEST.nativeValue
    val result =
      uri?.let {
        // `density` is what RN's PixelRatio reports to JS, so `resize` (dp)
        // means the same as in the app's layout maths.
        TurboImageCore.resolve(
          it, cacheKey, cachePolicy, processing, resources.displayMetrics.density.toDouble(), headers,
          allowDownscaling, resizeMode)
      }
        ?: ResolveFailure(errorCode = 1) // EmptyUri, same as the core's code
    when (result) {
      is ResolveFailure -> {
        emitFailure(invalid, "Invalid request (core error ${result.errorCode})")
        onLoadFailed()
        emitCompletion("completed")
      }
      is ResolvedRequest -> startLoad(result)
    }
  }

  private fun startLoad(request: ResolvedRequest) {
    emit("topStart") { putString("state", "running") }

    // Capture this load's identity so a late callback from a replaced load
    // cannot touch this view (same guard as the iOS view). See [inFlight].
    val thisLoad = Any()
    inFlight = thisLoad
    val thisHandle =
      loader.load(
        this as ImageView,
        request,
        ImageLoaderAdapter.DisplayOptions(fadeMillis = fadeDuration, allowHardware = allowHardware),
        object : ImageLoaderAdapter.Listener {
          override fun onProgress(completed: Long, total: Long) {
            if (inFlight !== thisLoad) return
            lastProgressTotal = total
            if (!progressThrottle.shouldReport(completed, total)) return
            emitProgress(completed, total)
          }

          override fun onSuccess(width: Int, height: Int) {
            if (inFlight !== thisLoad) return
            inFlight = null
            handle = null
            showingFinalImage = true
            showingPreviousImage = false
            // A successful load ends progress at 100% (core rule, see finish()):
            // Coil may decode a noCache response without reading it to EOF.
            if (progressThrottle.finish(lastProgressTotal)) {
              emitProgress(lastProgressTotal, lastProgressTotal)
            }
            emit("topSuccess") {
              putDouble("width", width.toDouble())
              putDouble("height", height.toDouble())
              putString("source", request.url)
            }
            emitCompletion("completed")
          }

          override fun onError(code: Int, message: String) {
            if (inFlight !== thisLoad) return
            inFlight = null
            handle = null
            emitFailure(code, message)
            onLoadFailed()
            emitCompletion("completed")
          }
        },
      )
    // Already finished if the callback ran inside `load()`: nothing to cancel.
    if (inFlight === thisLoad) handle = thisHandle
  }

  fun cancel() {
    handle?.cancel()
    handle = null
    inFlight = null
    ++placeholderGeneration // drop any decode still in flight
  }

  private fun emitFailure(code: Int, message: String) =
    emit("topFailure") {
      putString("code", TurboImageCore.loadErrorCodeName(code))
      putString("error", message)
    }

  private fun emitProgress(completed: Long, total: Long) =
    emit("topProgress") {
      putDouble("completed", completed.toDouble())
      putDouble("total", if (total > 0) total.toDouble() else -1.0)
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
