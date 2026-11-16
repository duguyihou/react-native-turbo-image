package com.turboimage.core

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
      /** Maps the codegen string union from TurboImageViewNativeComponent.ts. */
      fun fromJs(value: String?): CachePolicy =
        when (value) {
          "memoryOnly" -> MEMORY_ONLY
          "noCache" -> NO_CACHE
          "cacheOnly" -> CACHE_ONLY
          else -> DEFAULT
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

  /** The JS spelling of a load error code, owned by the C++ core. */
  fun loadErrorCodeName(code: Int): String = nativeLoadErrorCodeName(code)

  fun resolve(uri: String, cacheKey: String?, cachePolicy: CachePolicy): ResolveResult =
    nativeResolve(uri, cacheKey ?: "", cachePolicy.nativeValue)

  val coreVersion: String
    get() = nativeCoreVersion()

  private external fun nativeResolve(uri: String, cacheKey: String, cachePolicy: Int): ResolveResult

  private external fun nativeCoreVersion(): String

  private external fun nativeLoadErrorCodeName(code: Int): String
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
) : ResolveResult

/** Constructed from JNI; `errorCode` mirrors `turboimage::RequestError`. */
data class ResolveFailure(val errorCode: Int) : ResolveResult
