package com.turboimage.core

import android.graphics.Bitmap
import android.util.Log

/**
 * Kotlin face of the shared C++ core (cpp/). Android never re-implements
 * request semantics; it asks the core, exactly like the iOS Fabric view does.
 *
 * This object holds the core's functions and every JNI declaration (the
 * native library binds them by this class's name). The types they take and
 * return are next to it: `ImageRequest.kt`, `ProgressThrottle.kt`,
 * `ViewLifecycle.kt`.
 */
object TurboImageCore {
  init {
    System.loadLibrary("turboimage")
  }

  /** A `turboimage::CachePolicy` value, or -1 for an unknown spelling. */
  internal fun parseCachePolicy(js: String): Int = nativeParseCachePolicy(js)

  /**
   * The cache keys a `placeholder.memoryCacheKey` may name, in lookup order:
   * the key as written (an explicit `source.cacheKey`), then its canonical
   * form (a source URI). The core decides, so iOS tries the same keys.
   */
  fun memoryCacheKeyCandidates(key: String): Array<String> = nativeMemoryCacheKeyCandidates(key)

  /** The JS spelling of a load error code, owned by the C++ core. */
  fun loadErrorCodeName(code: Int): String = nativeLoadErrorCodeName(code)

  /** Resolves a view's [request]; [pixelRatio] converts `resize` from dp. */
  fun resolve(request: ImageRequest, pixelRatio: Double): ResolveResult =
    resolve(
      request.uri,
      request.cacheKey,
      request.cachePolicy,
      request.processing,
      pixelRatio,
      request.headers,
      request.allowDownscaling,
      request.resizeMode,
    )

  /**
   * [allowDownscaling] defaults to false here, unlike the view prop: the
   * cache module resolves without a view, and a prefetch has no view size to
   * decode to. Views always pass their prop.
   */
  fun resolve(
    uri: String,
    cacheKey: String?,
    cachePolicy: CachePolicy,
    processing: Processing = Processing(),
    pixelRatio: Double = 1.0,
    headers: List<Pair<String, String>> = emptyList(),
    allowDownscaling: Boolean = false,
    resizeMode: ResizeMode = ResizeMode.CONTAIN,
  ): ResolveResult =
    nativeResolve(
      uri,
      cacheKey ?: "",
      cachePolicy.nativeValue,
      processing.resize,
      processing.blur,
      processing.monochrome.toNativeColor(),
      processing.tint.toNativeColor(),
      pixelRatio,
      headers.flatMap { (name, value) -> listOf(name, value) }.toTypedArray(),
      allowDownscaling,
      resizeMode.nativeValue,
    )

  // An ARGB Int widened without sign extension, or -1 for "unset" (JNI side).
  private fun Int?.toNativeColor(): Long = this?.toLong()?.and(0xffffffffL) ?: -1L

  /**
   * Runs the processors a `ResolvedRequest.processorKey` describes over a
   * bitmap. Returns null if the key is invalid. Pure; call it off the main
   * thread (a 12 MP blur takes a few hundred ms).
   */
  fun process(input: Bitmap, processorKey: String): Bitmap? {
    // The core works on premultiplied RGBA8, which is exactly ARGB_8888's
    // memory layout. Other configs (RGB_565, RGBA_F16, HARDWARE) are copied.
    val source =
      if (input.config == Bitmap.Config.ARGB_8888) input
      else input.copy(Bitmap.Config.ARGB_8888, false) ?: return null
    // Reads `source`'s pixels and writes the result's in native code.
    return nativeProcess(source, processorKey)
  }

  val coreVersion: String
    get() = nativeCoreVersion()

  /**
   * Decodes a blurhash or base64 thumbhash with the shared C++ core. Pure and
   * thread-safe; call it off the main thread (it can take ~1 ms).
   *
   * Null when neither hash decodes, and also when the core ran out of memory:
   * a placeholder is optional, and this runs on an executor thread, where a
   * thrown error would take the app down.
   */
  fun decodePlaceholder(blurhash: String, thumbhash: String): PlaceholderPixels? =
    try {
      nativeDecodePlaceholder(blurhash, thumbhash)
    } catch (e: OutOfMemoryError) {
      Log.w("TurboImage", "Placeholder decode ran out of memory", e)
      null
    }

  // ---------------------------------------------------------------------
  // JNI declarations (android/src/main/cpp/TurboImageJni.cpp).
  //
  // Those used only above are private. The ones `ProgressThrottle` and
  // `ViewLifecycle` call are `internal`, and Kotlin would otherwise append
  // the module's name to an internal function's JVM name, which the native
  // library does not know: hence the `@JvmName` on each.

  private external fun nativeParseCachePolicy(js: String): Int

  private external fun nativeMemoryCacheKeyCandidates(key: String): Array<String>

  private external fun nativeLoadErrorCodeName(code: Int): String

  private external fun nativeCoreVersion(): String

  private external fun nativeResolve(
    uri: String,
    cacheKey: String,
    cachePolicy: Int,
    resize: Double,
    blur: Double,
    monochrome: Long,
    tint: Long,
    pixelRatio: Double,
    headers: Array<String>,
    allowDownscaling: Boolean,
    resizeMode: Int,
  ): ResolveResult

  private external fun nativeProcess(input: Bitmap, processorKey: String): Bitmap?

  private external fun nativeDecodePlaceholder(blurhash: String, thumbhash: String): PlaceholderPixels?

  @JvmName("nativeShouldReportProgress")
  internal external fun nativeShouldReportProgress(state: LongArray, completed: Long, total: Long): Boolean

  @JvmName("nativeFinishProgress")
  internal external fun nativeFinishProgress(state: LongArray, total: Long): Boolean

  @JvmName("nativeLifecycleReload")
  internal external fun nativeLifecycleReload(
    state: LongArray,
    recyclingKeyChanged: Boolean,
    imageOnScreen: Boolean,
    requestValid: Boolean,
    placeholder: Int,
    showPlaceholderOnFailure: Boolean,
  ): LongArray

  @JvmName("nativeLifecycleIsInFlight")
  internal external fun nativeLifecycleIsInFlight(state: LongArray, token: Long): Boolean

  @JvmName("nativeLifecycleLoadSucceeded")
  internal external fun nativeLifecycleLoadSucceeded(state: LongArray, token: Long): LongArray

  @JvmName("nativeLifecycleLoadFailed")
  internal external fun nativeLifecycleLoadFailed(
    state: LongArray,
    token: Long,
    placeholder: Int,
    showPlaceholderOnFailure: Boolean,
  ): LongArray

  @JvmName("nativeLifecycleApplyPlaceholder")
  internal external fun nativeLifecycleApplyPlaceholder(
    state: LongArray,
    placeholder: Int,
    showPlaceholderOnFailure: Boolean,
  ): LongArray

  @JvmName("nativeLifecyclePlaceholderDecoded")
  internal external fun nativeLifecyclePlaceholderDecoded(
    state: LongArray,
    generation: Long,
    placeholder: Int,
    showPlaceholderOnFailure: Boolean,
  ): Boolean

  @JvmName("nativeLifecycleDrop")
  internal external fun nativeLifecycleDrop(state: LongArray): LongArray

  @JvmName("nativeLifecycleStartUpgrade")
  internal external fun nativeLifecycleStartUpgrade(state: LongArray): Long

  @JvmName("nativeLifecycleIsUpgrading")
  internal external fun nativeLifecycleIsUpgrading(state: LongArray, token: Long): Boolean

  @JvmName("nativeLifecycleUpgradeSucceeded")
  internal external fun nativeLifecycleUpgradeSucceeded(state: LongArray, token: Long): Boolean

  @JvmName("nativeLifecycleUpgradeFailed")
  internal external fun nativeLifecycleUpgradeFailed(state: LongArray, token: Long)

  /** `turboimage::needsLargerDecode`; sizes in pixels. */
  @JvmName("nativeNeedsLargerDecode")
  internal external fun nativeNeedsLargerDecode(
    decodedWidth: Double,
    decodedHeight: Double,
    loadedForWidth: Double,
    loadedForHeight: Double,
    nowWidth: Double,
    nowHeight: Double,
    fill: Boolean,
  ): Boolean
}

/**
 * Premultiplied RGBA8, row-major: the in-memory layout of an ARGB_8888
 * Bitmap. Constructed from JNI; constructor pinned in consumer-rules.pro.
 */
class PlaceholderPixels(val width: Int, val height: Int, val rgba: ByteArray)
