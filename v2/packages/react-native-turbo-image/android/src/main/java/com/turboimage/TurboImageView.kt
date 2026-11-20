package com.turboimage

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Log
import android.widget.ImageView
import androidx.appcompat.widget.AppCompatImageView
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.events.Event
import com.turboimage.core.ImageRequest
import com.turboimage.core.LoadErrorCode
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
 * Fabric host view for <TurboImage> on Android. Mirrors
 * ios/Fabric/TurboImageComponentView.mm step for step:
 * props → C++ core → loader adapter → display + events.
 */
@SuppressLint("ViewConstructor")
class TurboImageView(
  private val reactContext: ThemedReactContext,
  private val loader: ImageLoaderAdapter,
) : AppCompatImageView(reactContext) {

  // Everything the props say about which image to load. The view manager
  // replaces it field by field; whether a change needs a new load is decided
  // once per transaction, by comparing it with [loadedFor].
  var request = ImageRequest()

  // Placeholder props. A change re-applies the placeholder; see [onTransactionEnd].
  var blurhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  var thumbhash: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }
  var memoryCacheKey: String? = null
    set(value) { if (field != value) { field = value; needsPlaceholder = true } }

  // Not a request prop: a new key alone starts no load, because the image on
  // screen is still the one the source names. It only decides how the load started
  // in this same transaction treats the previous image (see [reload]).
  var recyclingKey: String? = null
    set(value) { if (field != value) { field = value; recyclingKeyChanged = true } }

  /**
   * What decides a load besides the request: a change to either starts a new
   * one. [allowHardware] is not a request field (it never affects cache
   * keys), but an image decoded for one answer is wrong for the other.
   */
  private data class LoadInputs(val request: ImageRequest, val allowHardware: Boolean)

  // The inputs the current load was started for; null before the first load.
  private var loadedFor: LoadInputs? = null
  private var needsPlaceholder = false
  private var recyclingKeyChanged = false
  // Every decision about what the view shows and which load events JS sees
  // is the core's (`turboimage::ViewLifecycle`, the same code the iOS view
  // runs). This view says what happened and carries out the effects it gets
  // back; see [perform].
  private val lifecycle = ViewLifecycle()
  // Cancels the load in flight; null when there is none.
  private var handle: LoadHandle? = null
  private var progressThrottle = ProgressThrottle()
  // Last Content-Length seen this load, for the throttle's finish() step.
  private var lastProgressTotal = -1L

  /** 1.x semantics: false removes the placeholder when the load fails. */
  var showPlaceholderOnFailure = false

  /** Cross-fade duration in ms; 0 disables it. 1.x default. */
  var fadeDuration = 300

  /** 1.x prop: false decodes to a software bitmap. Changing it reloads. */
  var allowHardware = true

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

  // Keeps everything this view draws (the image, a placeholder, a cross-fade
  // between them) inside its border: within the border's width, and within
  // its rounded corners. The border itself is the view's background (see
  // [TurboImageBorders]), which is drawn before this and is not clipped.
  // Without a border this clips to the view's bounds, as `cropToPadding`
  // already did. The anti-aliased variant is what React Native's <Image>
  // uses; a plain clipPath leaves jagged corners on API 28 and below.
  override fun onDraw(canvas: Canvas) {
    BackgroundStyleApplicator.clipToPaddingBoxWithAntiAliasing(this, canvas) { super.onDraw(canvas) }
  }

  fun setResizeMode(mode: String?) {
    val (scale, core) =
      when (mode) {
        "cover" -> ScaleType.CENTER_CROP to ResizeMode.COVER
        "stretch" -> ScaleType.FIT_XY to ResizeMode.STRETCH
        "center" -> ScaleType.CENTER to ResizeMode.CENTER
        else -> ScaleType.FIT_CENTER to ResizeMode.CONTAIN // the default
      }
    scaleType = scale
    // A request prop as well as a drawing one: `contain` needs fewer pixels
    // than `cover`, and `center` needs them all (the core's decode-size
    // rule), so an image decoded for one mode can be too small for another.
    request = request.copy(resizeMode = core)
  }


  /** Called once per Fabric transaction, after all props have landed. */
  fun onTransactionEnd() {
    // A new load whenever the request differs from the one on screen, and
    // for the first transaction whatever it says: a view mounted without a
    // source reports that (`invalidRequest`) instead of staying silent.
    val inputs = LoadInputs(request, allowHardware)
    if (inputs != loadedFor) {
      loadedFor = inputs
      // A reload may clear the view, so the placeholder must be (re)applied.
      needsPlaceholder = true
      reload()
    }
    // Consumed by the load above, or dropped: the key applies only to a load
    // in its own transaction.
    recyclingKeyChanged = false
    if (needsPlaceholder) {
      needsPlaceholder = false
      perform(lifecycle.applyPlaceholder(placeholderKind(), showPlaceholderOnFailure))
    }
  }

  /** The view is gone for good ([TurboImageViewManager.onDropViewInstance]). */
  fun drop() = perform(lifecycle.drop())

  // JS allows one placeholder kind at a time; `memoryCacheKey` wins if an
  // app passes several anyway, as it always has.
  private fun placeholderKind() =
    when {
      !memoryCacheKey.isNullOrEmpty() -> PlaceholderKind.MEMORY_CACHE_KEY
      !blurhash.isNullOrEmpty() || !thumbhash.isNullOrEmpty() -> PlaceholderKind.HASH
      else -> PlaceholderKind.NONE
    }

  private fun reload() {
    progressThrottle = ProgressThrottle()
    lastProgressTotal = -1L
    // `density` is what RN's PixelRatio reports to JS, so `resize` (dp) means
    // the same as in the app's layout maths.
    val result = TurboImageCore.resolve(request, resources.displayMetrics.density.toDouble())
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
   * The effects that only one kind of step can produce, and that need what
   * that step knows: the request a reload resolved, or what the adapter
   * called back with. Each caller of [perform] overrides the ones its step
   * can produce, closing over that knowledge, so no effect has to dig its
   * context out of a loosely typed argument.
   *
   * The lifecycle never sends an effect from a step that cannot produce it
   * (`StartLoad` from a callback, say). If it ever did, that is a bug in the
   * core or here, reported by [unexpected] rather than acted on.
   */
  private open inner class StepEffects {
    open fun deliverInvalidRequest(): Unit = unexpected(Effect.Kind.DELIVER_INVALID_REQUEST)

    open fun startLoad(token: Long): Unit = unexpected(Effect.Kind.START_LOAD)

    open fun deliverSuccess(): Unit = unexpected(Effect.Kind.DELIVER_SUCCESS)

    open fun deliverFailure(): Unit = unexpected(Effect.Kind.DELIVER_FAILURE)
  }

  // Loud where a developer will see it, harmless where a user would: the
  // effect is skipped, which at worst leaves one image unloaded.
  private fun unexpected(kind: Effect.Kind) {
    val message = "TurboImage: the lifecycle sent $kind from a step that cannot produce it"
    if (BuildConfig.DEBUG) error(message)
    Log.e("TurboImage", message)
  }

  /**
   * Carries out the lifecycle's effects, in order. The lifecycle decided;
   * nothing here chooses whether an effect applies.
   */
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

  private fun startLoad(request: ResolvedRequest, token: Long) {
    emit("topStart") { putString("state", "running") }

    // The adapter drops callbacks after cancel, but the lifecycle guards by
    // token as well: a callback from a load that was replaced gets no
    // effects back, so it cannot touch this view.
    val thisHandle =
      loader.load(
        this as ImageView,
        request,
        ImageLoaderAdapter.DisplayOptions(fadeMillis = fadeDuration, allowHardware = allowHardware),
        object : ImageLoaderAdapter.Listener {
          override fun onProgress(completed: Long, total: Long) {
            if (!lifecycle.isInFlight(token)) return
            lastProgressTotal = total
            if (!progressThrottle.shouldReport(completed, total)) return
            emitProgress(completed, total)
          }

          override fun onSuccess(width: Int, height: Int) =
            perform(
              lifecycle.loadSucceeded(token),
              object : StepEffects() {
                override fun deliverSuccess() = deliverSuccess(width, height, request.url)
              })

          override fun onError(code: Int, message: String) =
            perform(
              lifecycle.loadFailed(token, placeholderKind(), showPlaceholderOnFailure),
              object : StepEffects() {
                override fun deliverFailure() = emitFailure(code, message)
              })
        },
      )
    // Already finished if the callback ran inside `load()` (a memory-cache
    // hit): there is nothing left to cancel, so the handle is not kept.
    if (lifecycle.isInFlight(token)) handle = thisHandle
  }

  // The adapter (Coil's target) has already put the image in this view; see
  // `DeliverSuccess` in the core.
  private fun deliverSuccess(width: Int, height: Int, url: String) {
    // A successful load ends progress at 100% (core rule, see finish()):
    // Coil may decode a noCache response without reading it to EOF.
    if (progressThrottle.finish(lastProgressTotal)) {
      emitProgress(lastProgressTotal, lastProgressTotal)
    }
    emit("topSuccess") {
      putDouble("width", width.toDouble())
      putDouble("height", height.toDouble())
      putString("source", url)
    }
  }

  // memoryCacheKey: a synchronous memory-cache lookup (no decode, no disk).
  // The core says which keys the prop may name (an explicit cacheKey as
  // written, or a URI's canonical form); the first hit wins, and a miss
  // clears the view.
  private fun showCachedPlaceholder() {
    setImageDrawable(
      TurboImageCore.memoryCacheKeyCandidates(memoryCacheKey.orEmpty())
        .firstNotNullOfOrNull { loader.memoryCachedDrawable(it, resources) })
  }

  private fun decodePlaceholder(generation: Long) {
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
