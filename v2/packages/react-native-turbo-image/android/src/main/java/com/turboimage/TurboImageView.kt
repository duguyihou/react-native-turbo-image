package com.turboimage

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.drawable.Drawable
import android.util.Log
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.WritableMap
import com.facebook.react.common.LifecycleState
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import com.turboimage.core.CachePolicy
import com.turboimage.core.ImageRequest
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.Processing
import com.turboimage.core.ProgressThrottle
import com.turboimage.core.ResizeMode
import com.turboimage.core.ResolveFailure
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import com.turboimage.core.ViewLifecycle
import com.turboimage.core.ViewLifecycle.Effect
import com.turboimage.core.ViewLifecycle.PlaceholderKind
import com.turboimage.loader.ImageLoaderAdapter
import com.turboimage.loader.LoadHandle
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Fabric host view for <TurboImage>: props → C++ core → loader adapter →
 * display + events. Mirrors the iOS component view.
 */
@SuppressLint("ViewConstructor")
class TurboImageView internal constructor(
  private val reactContext: ThemedReactContext,
  private val loader: ImageLoaderAdapter,
) : AppCompatImageView(reactContext) {

  // Which image to load; compared with [loadedFor] once per transaction.
  var request = ImageRequest()

  // Placeholder props; a change re-applies the placeholder.
  var blurhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  var thumbhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  var memoryCacheKey: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  // `placeholder.uri`; see [loadPlaceholder].
  var placeholderUri: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }

  // Starts no load by itself; only affects how a load in the same
  // transaction treats the previous image.
  var recyclingKey: String? = null
    set(value) { if (field != value) { field = value; recyclingKeyChanged = true } }

  /**
   * A change to either starts a new load. [allowHardware] is not in the
   * request (no cache-key effect) but still needs a fresh decode.
   */
  private data class LoadInputs(
    val request: ImageRequest,
    val allowHardware: Boolean,
  )

  // The inputs the current load was started for; null before the first load.
  private var loadedFor: LoadInputs? = null
  private var needsPlaceholder = false
  // Ignored when [needsPlaceholder] re-applies anyway.
  private var showPlaceholderOnFailureChanged = false
  private var recyclingKeyChanged = false
  // The core decides what is shown and which events fire (shared with iOS);
  // this view reports what happened and runs the returned effects.
  private val lifecycle = ViewLifecycle()
  // Cancels the load in flight; null when there is none.
  private var handle: LoadHandle? = null
  private var progressThrottle = ProgressThrottle()
  // Last Content-Length seen, for the throttle's finish().
  private var lastProgressTotal = -1L

  /**
   * The shown image if it was decoded for the view's size and can be reloaded
   * larger when the view grows; null otherwise. Sizes in pixels.
   */
  private data class Upgradable(
    val request: ResolvedRequest,
    val fill: Boolean,
    val decodedWidth: Int,
    val decodedHeight: Int,
    val loadedForWidth: Int,
    val loadedForHeight: Int,
  )

  private var upgradable: Upgradable? = null
  // Cancels the image placeholder's load; null when there is none.
  private var placeholderHandle: LoadHandle? = null

  /**
   * False removes the placeholder when the load fails. It decides only what
   * a failure shows, so a change alone redoes nothing elsewhere (see
   * [onTransactionEnd]).
   */
  var showPlaceholderOnFailure = false
    set(value) { if (field != value) { field = value; showPlaceholderOnFailureChanged = true } }

  /** Cross-fade duration in ms; 0 disables it. */
  var fadeDuration = 300

  /** False decodes to a software bitmap. Changing it reloads. */
  var allowHardware = true

  /** Whether JS has an `onProgress` handler. Read at load start; never reloads. */
  var progressEnabled = false

  /** Which load events JS has handlers for; [emit] sends only those. */
  var loadEventMask = ALL_LOAD_EVENTS

  // Trips to the background, counted by this view. A load that fails with
  // `network` after one was likely cut off by it, so it retries at once
  // (see `ViewLifecycle::retry`); any other network failure waits for the
  // next return to the foreground.
  private var backgroundTrips = 0L
  private var inForeground = reactContext.lifecycleState == LifecycleState.RESUMED
  // RN calls `onHostResume` at once if the host is already resumed: harmless,
  // since nothing has failed yet.
  private val hostListener =
    object : LifecycleEventListener {
      override fun onHostResume() {
        inForeground = true
        retryFailedLoad()
      }

      override fun onHostPause() {
        inForeground = false
        backgroundTrips++
      }

      override fun onHostDestroy() = Unit
    }

  init {
    // The spec default, `contain`.
    scaleType = ScaleType.FIT_CENTER
    // `cover` overflows the bounds, and Fabric parents don't clip children,
    // so clip here (like `clipsToBounds` on iOS).
    cropToPadding = true
    reactContext.addLifecycleEventListener(hostListener)
  }

  // Clips everything drawn to inside the border and its rounded corners.
  // Anti-aliased, as RN's <Image>: a plain clipPath is jagged on API <= 28.
  override fun onDraw(canvas: Canvas) {
    BackgroundStyleApplicator.clipToPaddingBoxWithAntiAliasing(this, canvas) { super.onDraw(canvas) }
  }

  fun setResizeMode(mode: String?) {
    val (scale, core) =
      when (mode) {
        "cover" -> ScaleType.CENTER_CROP to ResizeMode.COVER
        "stretch" -> ScaleType.FIT_XY to ResizeMode.STRETCH
        "center" -> ScaleType.CENTER to ResizeMode.CENTER
        "scale-down" -> ScaleType.CENTER_INSIDE to ResizeMode.SCALE_DOWN
        else -> ScaleType.FIT_CENTER to ResizeMode.CONTAIN // the default
      }
    centredScaleType = scale
    // Also a request prop: the decode size depends on the mode.
    request = request.copy(resizeMode = core)
    updatePlacement()
  }

  // `contentPosition` as fractions of the free space (0.5 = centred).
  var contentPositionX = 0.5
    set(value) { if (field != value) { field = value; updatePlacement() } }
  var contentPositionY = 0.5
    set(value) { if (field != value) { field = value; updatePlacement() } }

  // False while ImageView's constructor runs (see [updatePlacement]).
  private var constructed = false

  // The platform scale type for the mode, used when the image is centred.
  private var centredScaleType = ScaleType.FIT_CENTER

  /**
   * Places the image for the resize mode and `contentPosition`. Centred uses
   * the platform scale type; otherwise the core's `placeImage` (as on iOS)
   * becomes the image matrix. Rerun on drawable, size or prop changes.
   */
  private fun updatePlacement() {
    // ImageView's constructor calls in before our fields exist.
    if (!constructed) return
    val centred = contentPositionX == 0.5 && contentPositionY == 0.5
    if (centred || request.resizeMode == ResizeMode.STRETCH) {
      applyPlacement(centredScaleType, null)
      return
    }
    // The content box, inside the padding (the border).
    val boxWidth = width - paddingLeft - paddingRight
    val boxHeight = height - paddingTop - paddingBottom
    val image = drawable
    if (image == null || image.intrinsicWidth <= 0 || image.intrinsicHeight <= 0 || boxWidth <= 0 || boxHeight <= 0) {
      applyPlacement(centredScaleType, null)
      return
    }
    val (x, y, w, h) =
      TurboImageCore.placeImage(
          image.intrinsicWidth.toDouble(), image.intrinsicHeight.toDouble(),
          boxWidth.toDouble(), boxHeight.toDouble(),
          request.resizeMode, contentPositionX, contentPositionY)
        .map { it.toFloat() }
    placementMatrix.setScale(w / image.intrinsicWidth, h / image.intrinsicHeight)
    placementMatrix.postTranslate(x, y)
    applyPlacement(ScaleType.MATRIX, placementMatrix)
  }

  // Reused (`setImageMatrix` copies), saving a native allocation per call.
  private val placementMatrix = Matrix()
  private val nudgeMatrix = Matrix().apply { setTranslate(1f, 0f) }
  private val identityMatrix = Matrix()

  /**
   * Sets the scale type (and matrix) and applies them now. `setScaleType`
   * only requests a layout, which RN skips unless the frame changes; setting
   * a different matrix forces ImageView's `configureBounds` to run.
   */
  private fun applyPlacement(type: ScaleType, matrix: Matrix?) {
    if (scaleType != type) scaleType = type
    // The second set always differs from the first; both draw in one frame.
    imageMatrix = nudgeMatrix
    imageMatrix = matrix ?: identityMatrix
  }

  override fun setImageDrawable(drawable: Drawable?) {
    super.setImageDrawable(drawable)
    updatePlacement()
  }

  override fun setPadding(left: Int, top: Int, right: Int, bottom: Int) {
    super.setPadding(left, top, right, bottom)
    updatePlacement()
  }


  /** Called once per Fabric transaction, after all props have landed. */
  fun onTransactionEnd() {
    // Load on any change, and always on the first transaction, so a view
    // with no source reports `invalidRequest`.
    val inputs = LoadInputs(request, allowHardware)
    if (inputs != loadedFor) {
      loadedFor = inputs
      // A reload may clear the view, so the placeholder must be (re)applied.
      needsPlaceholder = true
      reload()
    }
    // The key only applies to a load in its own transaction.
    recyclingKeyChanged = false
    if (needsPlaceholder) {
      needsPlaceholder = false
      perform(lifecycle.applyPlaceholder(placeholderKind(), showPlaceholderOnFailure))
    } else if (showPlaceholderOnFailureChanged) {
      perform(lifecycle.showPlaceholderOnFailureChanged(placeholderKind(), showPlaceholderOnFailure))
    }
    showPlaceholderOnFailureChanged = false
  }

  /** The view is gone for good ([TurboImageViewManager.onDropViewInstance]). */
  fun drop() {
    reactContext.removeLifecycleEventListener(hostListener)
    upgradable = null
    cancelPlaceholderLoad()
    perform(lifecycle.drop())
  }

  // Growing may outgrow the decoded image.
  override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
    super.onSizeChanged(width, height, oldWidth, oldHeight)
    updatePlacement()
    if (width > oldWidth || height > oldHeight) upgradeIfOutgrown()
  }

  // `memoryCacheKey` wins if several kinds are set.
  private fun placeholderKind() =
    when {
      !memoryCacheKey.isNullOrEmpty() -> PlaceholderKind.MEMORY_CACHE_KEY
      // An image placeholder arrives async, like a decoded hash.
      !blurhash.isNullOrEmpty() || !thumbhash.isNullOrEmpty() || !placeholderUri.isNullOrEmpty() ->
        PlaceholderKind.HASH
      else -> PlaceholderKind.NONE
    }

  private fun reload() {
    // Nothing to upgrade until the new image arrives.
    upgradable = null
    progressThrottle = ProgressThrottle()
    lastProgressTotal = -1L
    val result = resolve(request)
    perform(
      lifecycle.reload(
        recyclingKeyChanged,
        imageOnScreen = drawable != null,
        // Requests the core rejects fail before onStart: no load ever began.
        requestValid = result is ResolvedRequest,
        placeholderKind(),
        showPlaceholderOnFailure,
      ),
      when (result) {
        is ResolvedRequest ->
          object : StepEffects() {
            override fun startLoad(token: Long) = startLoad(result, token)
          }
        is ResolveFailure ->
          object : StepEffects() {
            override fun deliverInvalidRequest() =
              emitFailure(
                LoadErrorCode.INVALID_REQUEST.nativeValue,
                "Invalid request (core error ${result.errorCode})")
          }
      },
    )
  }

  /**
   * The failed load again, if the core allows it (a network failure, nothing
   * since). Uses the request that failed, not props mid-transaction.
   */
  private fun retryFailedLoad() {
    if (!lifecycle.mayRetry()) return
    val result = loadedFor?.let { resolve(it.request) } as? ResolvedRequest ?: return
    progressThrottle = ProgressThrottle()
    lastProgressTotal = -1L
    perform(
      lifecycle.retry(placeholderKind(), showPlaceholderOnFailure),
      object : StepEffects() {
        override fun startLoad(token: Long) = startLoad(result, token)
      },
    )
  }

  /**
   * Step-specific effects; each [perform] caller overrides the ones its step
   * can produce. Any other effect is a bug, reported by [unexpected].
   */
  private open inner class StepEffects {
    open fun deliverInvalidRequest(): Unit = unexpected(Effect.Kind.DELIVER_INVALID_REQUEST)

    open fun startLoad(token: Long): Unit = unexpected(Effect.Kind.START_LOAD)

    open fun deliverSuccess(): Unit = unexpected(Effect.Kind.DELIVER_SUCCESS)

    open fun deliverFailure(): Unit = unexpected(Effect.Kind.DELIVER_FAILURE)
  }

  // Throws in debug; in release logs and skips the effect.
  private fun unexpected(kind: Effect.Kind) {
    val message = "TurboImage: the lifecycle sent $kind from a step that cannot produce it"
    if (BuildConfig.DEBUG) error(message)
    Log.e("TurboImage", message)
  }

  /** Runs the lifecycle's effects in order, without second-guessing them. */
  private fun perform(effects: List<Effect>, step: StepEffects = StepEffects()) {
    for (effect in effects) {
      when (effect.kind) {
        Effect.Kind.CANCEL_LOAD -> {
          handle?.cancel()
          handle = null
        }
        Effect.Kind.CLEAR_IMAGE -> setImageDrawable(null)
        Effect.Kind.EMIT_CANCELLED -> emitCompletion("cancelled")
        Effect.Kind.EMIT_COMPLETED -> emitCompletion("completed")
        Effect.Kind.DELIVER_INVALID_REQUEST -> step.deliverInvalidRequest()
        Effect.Kind.START_LOAD -> step.startLoad(token = effect.value)
        Effect.Kind.DELIVER_SUCCESS -> {
          handle = null
          step.deliverSuccess()
        }
        Effect.Kind.DELIVER_FAILURE -> {
          handle = null
          step.deliverFailure()
        }
        Effect.Kind.SHOW_CACHED_PLACEHOLDER -> showCachedPlaceholder()
        Effect.Kind.DECODE_PLACEHOLDER -> decodePlaceholder(generation = effect.value)
      }
    }
  }

  // `density` matches RN's PixelRatio, so `resize` (dp) matches JS layout.
  private fun resolve(request: ImageRequest) =
    TurboImageCore.resolve(request, resources.displayMetrics.density.toDouble())

  private fun emitStart() = emit("topStart") { putString("state", "running") }

  private fun startLoad(request: ResolvedRequest, token: Long) {
    emitStart()
    // The decode size if already laid out; otherwise the adapter waits for layout.
    val sizeAtStart = width to height
    // A load started in the background (the app runs briefly after a pause)
    // has not yet survived the trip it started in, so it counts as starting
    // before it: a failure after the return then retries at once.
    val tripsAtStart = backgroundTrips - if (inForeground) 0 else 1

    // The lifecycle also guards by token, so a stale callback does nothing.
    val thisHandle =
      loader.load(
        this as ImageView,
        request,
        ImageLoaderAdapter.DisplayOptions(
          fadeMillis = fadeDuration,
          allowHardware = allowHardware,
          reportProgress = progressEnabled,
        ),
        object : ImageLoaderAdapter.Listener {
          override fun onProgress(completed: Long, total: Long) {
            if (!lifecycle.isInFlight(token)) return
            lastProgressTotal = total
            if (!progressThrottle.shouldReport(completed, total)) return
            emitProgress(completed, total)
          }

          override fun onSuccess(width: Int, height: Int, animated: Boolean) =
            perform(
              lifecycle.loadSucceeded(token),
              object : StepEffects() {
                override fun deliverSuccess() {
                  cancelPlaceholderLoad()
                  deliverSuccess(width, height, request.url)
                  remember(request, width, height, animated, sizeAtStart)
                }
              })

          override fun onError(code: Int, message: String) {
            perform(
              lifecycle.loadFailed(token, placeholderKind(), showPlaceholderOnFailure, code, request.url),
              object : StepEffects() {
                override fun deliverFailure() = emitFailure(code, message)
              })
            // Cut off by a trip to the background and back: retry now. Still
            // in the background: `onHostResume` retries.
            if (backgroundTrips != tripsAtStart && inForeground) retryFailedLoad()
          }
        },
      )
    // A memory hit finishes inside `load()`; then there's nothing to keep.
    if (lifecycle.isInFlight(token)) handle = thisHandle
  }

  /** Records a view-sized image, then checks whether the view already outgrew it. */
  private fun remember(
    request: ResolvedRequest, width: Int, height: Int, animated: Boolean, sizeAtStart: Pair<Int, Int>,
  ) {
    val decode = request.decode as? ResolvedRequest.DecodeSize.View
    // Never upgrade an animation: the reload would restart it (as on iOS).
    if (decode == null || animated) {
      upgradable = null
      return
    }
    val (startWidth, startHeight) = sizeAtStart
    val laidOut = startWidth > 0 && startHeight > 0
    upgradable =
      Upgradable(
        request, decode.fill, width, height,
        loadedForWidth = if (laidOut) startWidth else this.width,
        loadedForHeight = if (laidOut) startHeight else this.height,
      )
    // The view may have grown while the load ran.
    upgradeIfOutgrown()
  }

  /**
   * Silently reloads at the view's size if the view outgrew the image; on
   * failure the shown image stays.
   */
  private fun upgradeIfOutgrown() {
    val shown = upgradable ?: return
    val nowWidth = width
    val nowHeight = height
    val outgrown =
      ViewLifecycle.needsLargerDecode(
        shown.decodedWidth, shown.decodedHeight,
        shown.loadedForWidth, shown.loadedForHeight,
        nowWidth, nowHeight, shown.fill)
    if (!outgrown) return
    val upgradeRequest = shown.request
    val token = lifecycle.startUpgrade()
    if (token == 0L) return
    val thisHandle =
      loader.load(
        this as ImageView,
        upgradeRequest,
        // No fade: the same picture, only sharper, replaces itself.
        ImageLoaderAdapter.DisplayOptions(fadeMillis = 0, allowHardware = allowHardware, reportProgress = false),
        object : ImageLoaderAdapter.Listener {
          override fun onProgress(completed: Long, total: Long) = Unit

          override fun onSuccess(width: Int, height: Int, animated: Boolean) {
            // Coil has painted it; false only if already cancelled.
            if (!lifecycle.upgradeSucceeded(token)) return
            handle = null
            upgradable =
              shown.copy(
                request = upgradeRequest,
                decodedWidth = width, decodedHeight = height,
                loadedForWidth = nowWidth, loadedForHeight = nowHeight)
            // It may have kept growing meanwhile.
            upgradeIfOutgrown()
          }

          override fun onError(code: Int, message: String) {
            if (!lifecycle.isUpgrading(token)) return
            lifecycle.upgradeFailed(token)
            handle = null
            // Don't retry at this size; a new source or reload starts over.
            upgradable = shown.copy(loadedForWidth = nowWidth, loadedForHeight = nowHeight)
          }
        },
      )
    if (lifecycle.isUpgrading(token)) handle = thisHandle
  }

  // The adapter has already put the image in this view.
  private fun deliverSuccess(width: Int, height: Int, url: String) {
    // End progress at 100%: Coil may not read a noCache response to EOF.
    if (progressThrottle.finish(lastProgressTotal)) {
      emitProgress(lastProgressTotal, lastProgressTotal)
    }
    emit("topSuccess") {
      putDouble("width", width.toDouble())
      putDouble("height", height.toDouble())
      putString("source", url)
    }
  }

  // Synchronous memory-cache lookup over the core's candidate keys; the
  // first hit wins, a miss clears the view.
  private fun showCachedPlaceholder() {
    setImageDrawable(
      TurboImageCore.memoryCacheKeyCandidates(memoryCacheKey.orEmpty())
        .firstNotNullOfOrNull { loader.memoryCachedDrawable(it, resources) })
  }

  private fun decodePlaceholder(generation: Long) {
    placeholderUri?.takeIf { it.isNotEmpty() }?.let {
      loadPlaceholder(it, generation)
      return
    }
    // Snapshot: props may change before the decode runs.
    val blur = blurhash.orEmpty()
    val thumb = thumbhash.orEmpty()
    placeholderExecutor.execute {
      val pixels = TurboImageCore.decodePlaceholder(blur, thumb) ?: return@execute
      val bitmap =
        Bitmap.createBitmap(pixels.width, pixels.height, Bitmap.Config.ARGB_8888).apply {
          // The core returns premultiplied RGBA, ARGB_8888's in-memory layout.
          copyPixelsFromBuffer(ByteBuffer.wrap(pixels.rgba))
        }
      post {
        // The image (or a newer placeholder) may have got there first.
        if (lifecycle.placeholderDecoded(generation, placeholderKind(), showPlaceholderOnFailure)) {
          setImageBitmap(bitmap)
        }
      }
    }
  }

  /**
   * Loads an image placeholder like the source (view size; headers only on
   * the source's origin) but unprocessed and without events; shown unless
   * something newer got there first.
   */
  private fun loadPlaceholder(uri: String, generation: Long) {
    cancelPlaceholderLoad()
    // The source's headers often carry credentials; another origin never gets them.
    val headers = if (TurboImageCore.sameOrigin(request.uri, uri)) request.headers else emptyList()
    val placeholder =
      resolve(
        request.copy(
          uri = uri, headers = headers, cacheKey = null, cachePolicy = CachePolicy.DEFAULT,
          processing = Processing(), allowDownscaling = true))
        as? ResolvedRequest ?: return // an unusable URI shows no placeholder
    var finished = false
    val handle =
      loader.loadPlaceholder(this, placeholder) { drawable ->
        finished = true
        placeholderHandle = null
        if (drawable != null && lifecycle.placeholderDecoded(generation, placeholderKind(), showPlaceholderOnFailure)) {
          setImageDrawable(drawable)
        }
      }
    // Already finished if the callback ran inside the call (a memory hit).
    if (!finished) placeholderHandle = handle
  }

  private fun cancelPlaceholderLoad() {
    placeholderHandle?.cancel()
    placeholderHandle = null
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
    // `topProgress` has no bit: `progressEnabled` decides it, at load start.
    val bit = LOAD_EVENT_BITS[name]
    if (bit != null && loadEventMask and bit == 0) return
    eventSink(name, payload)
  }

  /** Where events go. Replaced by instrumented tests, which have no React instance. */
  internal var eventSink: (name: String, payload: WritableMap.() -> Unit) -> Unit = { name, payload ->
    val event = TurboImageEvent(UIManagerHelper.getSurfaceId(this), id, name, Arguments.createMap().apply(payload))
    UIManagerHelper.getEventDispatcher(reactContext)?.dispatchEvent(event)
  }

  // Last, so every field above is initialised first.
  init {
    constructed = true
  }

  private companion object {
    // One thread: decodes are cheap, and serialising bounds memory.
    val placeholderExecutor: ExecutorService =
      Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "TurboImagePlaceholder").apply { isDaemon = true }
      }

    // `loadEventMask`'s bits, in the spec's order.
    val LOAD_EVENT_BITS = mapOf("topStart" to 1, "topSuccess" to 2, "topFailure" to 4, "topCompletion" to 8)
    const val ALL_LOAD_EVENTS = 15
  }

  // One class for all events. No coalescing, which could drop an
  // onStart/onCompletion pair.
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
