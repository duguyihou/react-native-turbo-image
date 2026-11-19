package com.turboimage.core

import android.graphics.Bitmap
import android.util.Log
import java.nio.ByteBuffer

/**
 * Kotlin face of the shared C++ core (cpp/). Android never re-implements
 * request semantics; it asks the core, exactly like the iOS Fabric view does.
 */
object TurboImageCore {
  init {
    System.loadLibrary("turboimage")
  }

  /** Mirrors `turboimage::CachePolicy`; the ints are a pinned ABI. */
  enum class CachePolicy(val nativeValue: Int) {
    DEFAULT(0),
    MEMORY_ONLY(1),
    NO_CACHE(2),
    CACHE_ONLY(3),
    URL_CACHE(4);

    companion object {
      /**
       * Parses the JS spelling with the core's parser (one parser for views
       * and the module, on both platforms). Unknown or null → DEFAULT.
       */
      fun fromJs(value: String?): CachePolicy {
        val native = nativeParseCachePolicy(value.orEmpty())
        return entries.firstOrNull { it.nativeValue == native } ?: DEFAULT
      }
    }
  }

  /** Mirrors `turboimage::ResizeMode`; the ints are a pinned ABI. */
  enum class ResizeMode(val nativeValue: Int) {
    CONTAIN(0),
    COVER(1),
    STRETCH(2),
    CENTER(3),
  }

  /** Mirrors `turboimage::LoadErrorCode`; the ints are a pinned ABI. */
  enum class LoadErrorCode(val nativeValue: Int) {
    UNKNOWN(0),
    INVALID_REQUEST(1),
    NOT_CACHED(2),
    NETWORK(3),
    DECODE(4),
  }

  /**
   * The cache keys a `placeholder.memoryCacheKey` may name, in lookup order:
   * the key as written (an explicit `source.cacheKey`), then its canonical
   * form (a source URI). The core decides, so iOS tries the same keys.
   */
  fun memoryCacheKeyCandidates(key: String): Array<String> = nativeMemoryCacheKeyCandidates(key)

  private external fun nativeParseCachePolicy(js: String): Int

  private external fun nativeMemoryCacheKeyCandidates(key: String): Array<String>

  /** The JS spelling of a load error code, owned by the C++ core. */
  fun loadErrorCodeName(code: Int): String = nativeLoadErrorCodeName(code)

  /**
   * Image processors as the view receives them (see
   * cpp/include/turboimage/Processing.h). `resize` is in dp; colours are
   * ARGB ints, null when unset.
   */
  data class Processing(
    val resize: Double = 0.0,
    val blur: Double = 0.0,
    val monochrome: Int? = null,
    val tint: Int? = null,
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
    val bytes = ByteArray(source.byteCount)
    source.copyPixelsToBuffer(ByteBuffer.wrap(bytes))
    val pixels = nativeProcess(bytes, source.width, source.height, processorKey) ?: return null
    return Bitmap.createBitmap(pixels.width, pixels.height, Bitmap.Config.ARGB_8888).apply {
      copyPixelsFromBuffer(ByteBuffer.wrap(pixels.rgba))
    }
  }

  private external fun nativeProcess(rgba: ByteArray, width: Int, height: Int, processorKey: String): PlaceholderPixels?

  val coreVersion: String
    get() = nativeCoreVersion()

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

  private external fun nativeCoreVersion(): String

  private external fun nativeLoadErrorCodeName(code: Int): String

  /**
   * Decodes a blurhash or base64 thumbhash with the shared C++ core. Pure and
   * thread-safe; call it off the main thread (it can take ~1 ms).
   */
  /**
   * Per-load progress throttle; the rule lives in the C++ core
   * (`turboimage::ProgressThrottle`). Holds only state, owned by one view and
   * used on the main thread.
   */
  class ProgressThrottle {
    // Mirrors ProgressThrottle's fields: lastPercent, lastReportedBytes,
    // reportedCompletion. Initial values match the C++ defaults.
    private val state = longArrayOf(-1L, -1L, 0L)

    fun shouldReport(completed: Long, total: Long): Boolean =
      nativeShouldReportProgress(state, completed, total)

    /** True if a final {total, total} event must still be emitted on success. */
    fun finish(total: Long): Boolean = nativeFinishProgress(state, total)
  }

  private external fun nativeFinishProgress(state: LongArray, total: Long): Boolean

  private external fun nativeShouldReportProgress(state: LongArray, completed: Long, total: Long): Boolean

  /**
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

  private external fun nativeDecodePlaceholder(blurhash: String, thumbhash: String): PlaceholderPixels?
}

sealed interface ResolveResult

/** Constructed from JNI; constructor signature is pinned in consumer-rules.pro. */
data class ResolvedRequest(
  val url: String,
  val cacheKey: String,
  val memoryRead: Boolean,
  val memoryWrite: Boolean,
  val diskRead: Boolean,
  val diskWrite: Boolean,
  val allowNetwork: Boolean,
  /**
   * Empty when unprocessed. Otherwise the identity *and* full description of
   * the processing step: adapters key memory variants by it (with
   * `cacheKey` naming the shared original) and pass it to
   * [TurboImageCore.process].
   */
  val processorKey: String,
  /** Validated headers as alternating names and values (the JNI shape). */
  private val headerFields: Array<String>,
  /**
   * The disk tier is the HTTP cache (`cachePolicy="urlCache"`): keyed by
   * [url], obeying `Cache-Control`, and separate from the disk cache
   * [cacheKey] addresses. See `ResolvedRequest::httpCache` in the core.
   */
  val httpCache: Boolean,
  private val decodeKind: Int,
  private val decodeWidth: Int,
  private val decodeFill: Boolean,
  private val vectorDecodeKind: Int,
  private val vectorDecodeWidth: Int,
  private val vectorDecodeFill: Boolean,
) : ResolveResult {
  /** How large to decode; mirrors `turboimage::DecodeSize`. */
  sealed interface DecodeSize {
    /** Every pixel of the source. */
    data object Original : DecodeSize

    /** The target view's size. [fill]: cover it; otherwise fit inside it. */
    data class View(val fill: Boolean) : DecodeSize

    /** This many pixels wide, aspect kept. */
    data class Width(val pixels: Int) : DecodeSize
  }

  val decode: DecodeSize
    get() = decodeSize(decodeKind, decodeWidth, decodeFill)

  /**
   * The size to draw the image at if it has no pixels of its own (SVG);
   * see `ResolvedRequest::vectorDecode` in the core. Differs from [decode]
   * only when `allowDownscaling` is off. [DecodeSize.Original] here is the
   * image's own size in dp.
   */
  val vectorDecode: DecodeSize
    get() = decodeSize(vectorDecodeKind, vectorDecodeWidth, vectorDecodeFill)

  private fun decodeSize(kind: Int, width: Int, fill: Boolean): DecodeSize =
    when (kind) {
      1 -> DecodeSize.View(fill)
      2 -> DecodeSize.Width(width)
      else -> DecodeSize.Original
    }

  /** Request headers in order; never part of a cache key. */
  val headers: List<Pair<String, String>>
    get() = headerFields.toList().chunked(2) { (name, value) -> name to value }

  // A data class compares arrays by identity; compare their contents.
  override fun equals(other: Any?): Boolean =
    other is ResolvedRequest &&
      url == other.url && cacheKey == other.cacheKey &&
      memoryRead == other.memoryRead && memoryWrite == other.memoryWrite &&
      diskRead == other.diskRead && diskWrite == other.diskWrite &&
      allowNetwork == other.allowNetwork && processorKey == other.processorKey &&
      httpCache == other.httpCache && decode == other.decode &&
      vectorDecode == other.vectorDecode &&
      headerFields.contentEquals(other.headerFields)

  override fun hashCode(): Int =
    listOf(url, cacheKey, memoryRead, memoryWrite, diskRead, diskWrite, allowNetwork, processorKey, httpCache, decode, vectorDecode)
      .hashCode() * 31 + headerFields.contentHashCode()
}

/**
 * Premultiplied RGBA8, row-major: the in-memory layout of an ARGB_8888
 * Bitmap. Constructed from JNI; constructor pinned in consumer-rules.pro.
 */
class PlaceholderPixels(val width: Int, val height: Int, val rgba: ByteArray)

/** Constructed from JNI; `errorCode` mirrors `turboimage::RequestError`. */
data class ResolveFailure(val errorCode: Int) : ResolveResult
