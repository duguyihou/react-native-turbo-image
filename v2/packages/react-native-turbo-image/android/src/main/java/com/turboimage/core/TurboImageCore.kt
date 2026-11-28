package com.turboimage.core

import android.graphics.Bitmap
import android.util.Log

/**
 * Kotlin face of the shared C++ core; Android never re-implements request
 * semantics. Holds every JNI declaration (bound by this class's name).
 */
object TurboImageCore {
  init {
    System.loadLibrary("turboimage")
  }

  /** A `turboimage::CachePolicy` value, or -1 for an unknown spelling. */
  internal fun parseCachePolicy(js: String): Int = nativeParseCachePolicy(js)

  /** Keys a `placeholder.memoryCacheKey` may name, in lookup order (same as iOS). */
  fun memoryCacheKeyCandidates(key: String): Array<String> = nativeMemoryCacheKeyCandidates(key)

  /** The JS spelling of a load error code, owned by the C++ core. */
  fun loadErrorCodeName(code: Int): String = nativeLoadErrorCodeName(code)

  /** Whether [a] and [b] share scheme, host and port (`turboimage::sameOrigin`). */
  fun sameOrigin(a: String, b: String): Boolean = nativeSameOrigin(a, b)

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

  /** [allowDownscaling] defaults to false: the cache module has no view size. */
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

  /** Resolves a source for the cache module, at original size. */
  fun resolveForCache(
    uri: String,
    cacheKey: String?,
    cachePolicy: CachePolicy,
    headers: List<Pair<String, String>>,
  ): ResolveResult = resolve(uri, cacheKey, cachePolicy, headers = headers, allowDownscaling = false)

  // ARGB widened without sign extension; -1 means unset.
  private fun Int?.toNativeColor(): Long = this?.toLong()?.and(0xffffffffL) ?: -1L

  /** Applies a `processorKey` to a bitmap; null if the key is invalid. Call off the main thread. */
  fun process(input: Bitmap, processorKey: String): Bitmap? {
    // The core needs ARGB_8888 (premultiplied RGBA8); copy other configs.
    val source =
      if (input.config == Bitmap.Config.ARGB_8888) input
      else input.copy(Bitmap.Config.ARGB_8888, false) ?: return null
    return nativeProcess(source, processorKey)
  }

  val coreVersion: String
    get() = nativeCoreVersion()

  /**
   * Decodes a blurhash or thumbhash; call off the main thread. Null on failure
   * or OOM: a throw on the executor thread would crash the app.
   */
  fun decodePlaceholder(blurhash: String, thumbhash: String): PlaceholderPixels? =
    try {
      nativeDecodePlaceholder(blurhash, thumbhash)
    } catch (e: OutOfMemoryError) {
      Log.w("TurboImage", "Placeholder decode ran out of memory", e)
      null
    }

  // ---------------------------------------------------------------------
  // JNI declarations (TurboImageJni.cpp). `internal` ones need `@JvmName`,
  // or Kotlin mangles the JVM name and JNI can't bind it.

  private external fun nativeParseCachePolicy(js: String): Int

  private external fun nativeMemoryCacheKeyCandidates(key: String): Array<String>

  private external fun nativeLoadErrorCodeName(code: Int): String

  private external fun nativeSameOrigin(a: String, b: String): Boolean

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
    code: Int,
  ): LongArray

  @JvmName("nativeLifecycleRetry")
  internal external fun nativeLifecycleRetry(
    state: LongArray,
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

  /** `turboimage::placeImage`: the (x, y, width, height) to draw the image in the box. */
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

/** Premultiplied RGBA8 (ARGB_8888's layout). Built from JNI; kept in consumer-rules.pro. */
class PlaceholderPixels(val width: Int, val height: Int, val rgba: ByteArray)
