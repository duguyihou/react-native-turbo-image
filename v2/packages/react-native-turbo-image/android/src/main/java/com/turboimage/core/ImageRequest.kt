package com.turboimage.core

// Kotlin mirrors of cpp/include/turboimage/ImageRequest.h. The integers are
// a pinned ABI, static_asserted in `TurboImageJni.cpp`.

/** Mirrors `turboimage::CachePolicy`. */
enum class CachePolicy(val nativeValue: Int) {
  DEFAULT(0),
  MEMORY_ONLY(1),
  NO_CACHE(2),
  CACHE_ONLY(3),
  URL_CACHE(4);

  companion object {
    /** Parses the JS spelling via the core. Unknown or null → DEFAULT. */
    fun fromJs(value: String?): CachePolicy {
      val native = TurboImageCore.parseCachePolicy(value.orEmpty())
      return entries.firstOrNull { it.nativeValue == native } ?: DEFAULT
    }
  }
}

/** Mirrors `turboimage::ResizeMode`. */
enum class ResizeMode(val nativeValue: Int) {
  CONTAIN(0),
  COVER(1),
  STRETCH(2),
  CENTER(3),
  SCALE_DOWN(4),
}

/** Mirrors `turboimage::LoadErrorCode`. */
enum class LoadErrorCode(val nativeValue: Int) {
  UNKNOWN(0),
  INVALID_REQUEST(1),
  NOT_CACHED(2),
  NETWORK(3),
  DECODE(4),
}

/** Image processors from props. `resize` is in dp; colours are ARGB, null when unset. */
data class Processing(
  val resize: Double = 0.0,
  val blur: Double = 0.0,
  val monochrome: Int? = null,
  val tint: Int? = null,
)

/**
 * Mirrors `turboimage::ImageRequest`. Equal requests are the same load; the
 * view reloads when this changes. No source is an empty [uri].
 */
data class ImageRequest(
  val uri: String = "",
  val cacheKey: String? = null,
  val headers: List<Pair<String, String>> = emptyList(),
  val cachePolicy: CachePolicy = CachePolicy.DEFAULT,
  val processing: Processing = Processing(),
  val allowDownscaling: Boolean = true,
  val resizeMode: ResizeMode = ResizeMode.CONTAIN,
)

// `turboimage::DecodeSize::Kind` values.
private const val DECODE_VIEW = 1
private const val DECODE_WIDTH = 2

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
   * Empty when unprocessed. Otherwise both the memory-variant key and the
   * full description passed to [TurboImageCore.process].
   */
  val processorKey: String,
  /** Validated headers as alternating names and values (the JNI shape). */
  private val headerFields: Array<String>,
  /** `urlCache`: the disk tier is the HTTP cache, keyed by [url], obeying `Cache-Control`. */
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
   * Render size for vector images (SVG). Differs from [decode] only when
   * `allowDownscaling` is off; [DecodeSize.Original] means its size in dp.
   */
  val vectorDecode: DecodeSize
    get() = decodeSize(vectorDecodeKind, vectorDecodeWidth, vectorDecodeFill)

  private fun decodeSize(kind: Int, width: Int, fill: Boolean): DecodeSize =
    when (kind) {
      DECODE_VIEW -> DecodeSize.View(fill)
      DECODE_WIDTH -> DecodeSize.Width(width)
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

/** Constructed from JNI; `errorCode` mirrors `turboimage::RequestError`. */
data class ResolveFailure(val errorCode: Int) : ResolveResult
