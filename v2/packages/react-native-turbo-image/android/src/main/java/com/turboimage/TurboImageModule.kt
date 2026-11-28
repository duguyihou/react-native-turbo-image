package com.turboimage

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.UiThreadUtil
import com.turboimage.core.CachePolicy
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import com.turboimage.core.readHeaders
import com.turboimage.core.resolveSourceUri
import com.turboimage.loader.CacheSizes
import com.turboimage.loader.LoadHandle
import com.turboimage.loader.TurboImageLoaders

/**
 * Cache-management TurboModule. Sources resolve through the C++ core like a
 * view's, so prefetched entries match the keys a view will hit.
 */
class TurboImageModule(private val context: ReactApplicationContext) :
  NativeTurboImageModuleSpec(context) {

  // In-flight prefetches, kept alive until they settle. Main thread only.
  private val prefetches = mutableSetOf<LoadHandle>()

  override fun getName() = NAME

  // null for invalid input.
  private fun resolve(sources: ReadableArray, index: Int, policy: CachePolicy, prefetch: Boolean = false): ResolvedRequest? {
    if (sources.getType(index) != ReadableType.Map) return null
    return resolve(sources.getMap(index) ?: return null, policy, prefetch)
  }

  // See `TurboImageCore.resolveForCache`.
  private fun resolve(source: ReadableMap, policy: CachePolicy, prefetch: Boolean = false): ResolvedRequest? {
    val uri = resolveSourceUri(context, if (source.hasKey("uri")) source.getString("uri").orEmpty() else "")
    val cacheKey = if (source.hasKey("cacheKey")) source.getString("cacheKey") else null
    return TurboImageCore.resolveForCache(
      uri,
      cacheKey,
      policy,
      readHeaders(source),
      prefetch,
    ) as? ResolvedRequest
  }

  override fun prefetch(
    sources: ReadableArray,
    cachePolicy: String,
    promise: Promise,
  ) {
    // The loader seam is main-thread only.
    UiThreadUtil.runOnUiThread {
      val loader = TurboImageLoaders.get(context)
      val policy = CachePolicy.fromJs(cachePolicy)
      var pending = sources.size()
      var allSucceeded = true
      if (pending == 0) {
        promise.resolve(true)
        return@runOnUiThread
      }
      fun finishOne(succeeded: Boolean) {
        allSucceeded = allSucceeded && succeeded
        if (--pending == 0) promise.resolve(allSucceeded)
      }
      for (i in 0 until sources.size()) {
        val request = resolve(sources, i, policy, prefetch = true)
        if (request == null) {
          finishOne(false)
          continue
        }
        // A memory hit calls back inside `prefetch()`, before `handle` is set;
        // `done` keeps that finished handle out of the set so it can't leak.
        var done = false
        var handle: LoadHandle? = null
        handle =
          loader.prefetch(request) { succeeded ->
            done = true
            handle?.let { prefetches.remove(it) }
            finishOne(succeeded)
          }
        if (!done) prefetches.add(handle)
      }
    }
  }

  override fun getSize(source: ReadableMap, cachePolicy: String, promise: Promise) {
    UiThreadUtil.runOnUiThread {
      val request = resolve(source, CachePolicy.fromJs(cachePolicy))
      if (request == null) {
        promise.reject(TurboImageCore.loadErrorCodeName(LoadErrorCode.INVALID_REQUEST.nativeValue), "Invalid request")
        return@runOnUiThread
      }
      // Kept until it settles; `done` as in `prefetch`.
      var done = false
      var handle: LoadHandle? = null
      fun settled() {
        done = true
        handle?.let { prefetches.remove(it) }
      }
      handle =
        TurboImageLoaders.get(context)
          .imageSize(
            request,
            onSize = { width, height ->
              settled()
              promise.resolve(
                Arguments.createMap().apply {
                  putDouble("width", width.toDouble())
                  putDouble("height", height.toDouble())
                })
            },
            onError = { code, message ->
              settled()
              promise.reject(TurboImageCore.loadErrorCodeName(code), message)
            },
          )
      if (!done) prefetches.add(handle)
    }
  }

  // Runs on the JS thread; TurboImageLoaders is synchronised for it.
  override fun configureCache(maxDiskSize: Double, maxMemoryCost: Double): Boolean =
    TurboImageLoaders.configureCache(CacheSizes(maxDiskSize.toLong(), maxMemoryCost.toLong()))

  override fun dispose(sources: ReadableArray, promise: Promise) {
    UiThreadUtil.runOnUiThread {
      // The policy does not affect the key.
      val requests =
        (0 until sources.size()).mapNotNull { resolve(sources, it, CachePolicy.DEFAULT) }
      TurboImageLoaders.get(context).remove(requests) { settle(promise, it) }
    }
  }

  override fun clearMemoryCache(promise: Promise) {
    UiThreadUtil.runOnUiThread {
      TurboImageLoaders.get(context).clearMemoryCache()
      promise.resolve(null)
    }
  }

  override fun clearDiskCache(promise: Promise) {
    UiThreadUtil.runOnUiThread {
      TurboImageLoaders.get(context).clearDiskCache { settle(promise, it) }
    }
  }

  // Only a failed disk-cache write rejects (Android only).
  private fun settle(promise: Promise, failure: Throwable?) {
    if (failure == null) promise.resolve(null)
    else promise.reject("disk", failure.message ?: "Disk cache operation failed", failure)
  }

  // Cancel prefetches on teardown. Promises stay unsettled on purpose: their
  // JS runtime is going away too.
  override fun invalidate() {
    UiThreadUtil.runOnUiThread {
      prefetches.forEach { it.cancel() }
      prefetches.clear()
    }
    super.invalidate()
  }

  companion object {
    const val NAME = "TurboImageModule"
  }
}
