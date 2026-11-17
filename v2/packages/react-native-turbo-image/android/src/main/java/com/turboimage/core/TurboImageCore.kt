package com.turboimage.core

import android.graphics.Bitmap
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
    CACHE_ONLY(3);

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

  /** Mirrors `turboimage::LoadErrorCode`; the ints are a pinned ABI. */
  enum class LoadErrorCode(val nativeValue: Int) {
    UNKNOWN(0),
    INVALID_REQUEST(1),
    NOT_CACHED(2),
    NETWORK(3),
    DECODE(4),
  }

  /** The core's canonical cache key for a URI (or explicit key). */
  fun canonicalCacheKey(uri: String): String = nativeCanonicalCacheKey(uri)

  private external fun nativeParseCachePolicy(js: String): Int

  private external fun nativeCanonicalCacheKey(uri: String): String

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

  fun resolve(
    uri: String,
    cacheKey: String?,
    cachePolicy: CachePolicy,
    processing: Processing = Processing(),
    pixelRatio: Double = 1.0,
    headers: List<Pair<String, String>> = emptyList(),
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

  fun decodePlaceholder(blurhash: String, thumbhash: String): PlaceholderPixels? =
    nativeDecodePlaceholder(blurhash, thumbhash)

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
) : ResolveResult {
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
      headerFields.contentEquals(other.headerFields)

  override fun hashCode(): Int =
    listOf(url, cacheKey, memoryRead, memoryWrite, diskRead, diskWrite, allowNetwork, processorKey)
      .hashCode() * 31 + headerFields.contentHashCode()
}

/**
 * Premultiplied RGBA8, row-major: the in-memory layout of an ARGB_8888
 * Bitmap. Constructed from JNI; constructor pinned in consumer-rules.pro.
 */
class PlaceholderPixels(val width: Int, val height: Int, val rgba: ByteArray)

/** Constructed from JNI; `errorCode` mirrors `turboimage::RequestError`. */
data class ResolveFailure(val errorCode: Int) : ResolveResult
