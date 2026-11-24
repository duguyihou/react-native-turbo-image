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

  /**
   * Resolves a source for the cache module (`prefetch`, `getSize`,
   * `dispose`), which has no view.
   *
   * Without [resize]: the original, unprocessed and not downscaled, as
   * there is no view size to decode to. With it: exactly what a view with
   * that `resize` prop, no other processing and `allowDownscaling` on
   * resolves at the same [pixelRatio], whatever its `resizeMode` or size
   * (a `resize` decode depends on neither), so a prefetch's memory entry is
   * the one that view looks up. `CacheTest` pins that equality.
   */
  fun resolveForCache(
    uri: String,
    cacheKey: String?,
    cachePolicy: CachePolicy,
    headers: List<Pair<String, String>>,
    resize: Double,
    pixelRatio: Double,
  ): ResolveResult =
    resolve(
      uri,
      cacheKey,
      cachePolicy,
      processing = Processing(resize = resize),
      pixelRatio = pixelRatio,
      headers = headers,
      allowDownscaling = resize > 0,
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

  /**
   * `turboimage::chooseSource`: the index of the candidate a view of
   * [viewWidth]×[viewHeight] pixels loads. [sizes] are the candidates'
   * sizes in pixels, flattened as (width, height) pairs.
   */
  fun chooseSource(
    sizes: DoubleArray,
    viewWidth: Int,
    viewHeight: Int,
    resizeMode: ResizeMode,
    allowDownscaling: Boolean,
  ): Int = nativeChooseSource(sizes, viewWidth.toDouble(), viewHeight.toDouble(), resizeMode.nativeValue, allowDownscaling)

  /** `turboimage::largerSourceFor`, or null when no larger candidate applies. */
  fun largerSourceFor(
    sizes: DoubleArray,
    current: Int,
    nowWidth: Int,
    nowHeight: Int,
    resizeMode: ResizeMode,
    allowDownscaling: Boolean,
  ): Int? =
    nativeLargerSourceFor(
      sizes, current, nowWidth.toDouble(), nowHeight.toDouble(), resizeMode.nativeValue, allowDownscaling)
      .takeIf { it >= 0 }

  private external fun nativeChooseSource(
    sizes: DoubleArray,
    viewWidth: Double,
    viewHeight: Double,
    resizeMode: Int,
    allowDownscaling: Boolean,
  ): Int

  private external fun nativeLargerSourceFor(
    sizes: DoubleArray,
    current: Int,
    nowWidth: Double,
    nowHeight: Double,
    resizeMode: Int,
    allowDownscaling: Boolean,
  ): Int

  /**
   * `turboimage::placeImage`: the rectangle (x, y, width, height) an image of
   * [imageWidth]×[imageHeight] is drawn in, inside a box of
   * [boxWidth]×[boxHeight] with its origin at 0,0.
   */
  fun placeImage(
    imageWidth: Double,
    imageHeight: Double,
    boxWidth: Double,
    boxHeight: Double,
    resizeMode: ResizeMode,
    positionX: Double,
    positionY: Double,
  ): DoubleArray =
    nativePlaceImage(imageWidth, imageHeight, boxWidth, boxHeight, resizeMode.nativeValue, positionX, positionY)

  private external fun nativePlaceImage(
    imageWidth: Double,
    imageHeight: Double,
    boxWidth: Double,
    boxHeight: Double,
    resizeMode: Int,
    positionX: Double,
    positionY: Double,
  ): DoubleArray

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
