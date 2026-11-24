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
 * Cache-management TurboModule (Android), the counterpart of
 * ios/Fabric/TurboImageModule.mm. Every source goes through the C++ core
 * first, like a view's source, so prefetched entries are exactly the ones a
 * view will later hit.
 */
class TurboImageModule(private val context: ReactApplicationContext) :
  NativeTurboImageModuleSpec(context) {

  // In-flight prefetches, kept so they are not garbage-collected mid-flight.
  // Main thread only.
  private val prefetches = mutableSetOf<LoadHandle>()

  override fun getName() = NAME

  // `{ uri, cacheKey? }` from JS → core resolution. null for invalid input.
  private fun resolve(sources: ReadableArray, index: Int, policy: CachePolicy): ResolvedRequest? {
    if (sources.getType(index) != ReadableType.Map) return null
    return resolve(sources.getMap(index) ?: return null, policy)
  }

  private fun resolve(source: ReadableMap, policy: CachePolicy): ResolvedRequest? {
    val uri = resolveSourceUri(context, if (source.hasKey("uri")) source.getString("uri").orEmpty() else "")
    val cacheKey = if (source.hasKey("cacheKey")) source.getString("cacheKey") else null
    return TurboImageCore.resolve(uri, cacheKey, policy, headers = readHeaders(source)) as? ResolvedRequest
  }

  override fun prefetch(sources: ReadableArray, cachePolicy: String, destination: String, promise: Promise) {
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
        val request = resolve(sources, i, policy)?.let { if (destination == "disk") diskOnly(it) else it }
        if (request == null) {
          finishOne(false)
          continue
        }
        // A prefetch already in the memory cache calls back inside
        // `prefetch()`, before `handle` is assigned. `done` records that, so
        // a finished handle (which pins the decoded bitmap through Coil's
        // result) is never added to the set with nothing left to remove it.
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

  // `destination: 'disk'`: the memory write off, which tells the adapter not
  // to decode at all (`ImageLoaderAdapter.prefetch`). A request with no disk
  // tier (`memoryOnly`, a local file) keeps its memory write, or the
  // prefetch would store nothing.
  private fun diskOnly(request: ResolvedRequest): ResolvedRequest =
    if (request.diskWrite) request.copy(memoryWrite = false) else request

  override fun getSize(source: ReadableMap, cachePolicy: String, promise: Promise) {
    UiThreadUtil.runOnUiThread {
      val request = resolve(source, CachePolicy.fromJs(cachePolicy))
      if (request == null) {
        promise.reject(TurboImageCore.loadErrorCodeName(LoadErrorCode.INVALID_REQUEST.nativeValue), "Invalid request")
        return@runOnUiThread
      }
      // Kept like a prefetch until it settles; `done` as there, for a
      // callback that runs inside `imageSize()`.
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

  // Synchronous, on the JS thread: TurboImageLoaders is synchronised for it.
  override fun configureCache(maxDiskSize: Double, maxMemoryCost: Double): Boolean =
    TurboImageLoaders.configureCache(CacheSizes(maxDiskSize.toLong(), maxMemoryCost.toLong()))

  override fun dispose(sources: ReadableArray, promise: Promise) {
    UiThreadUtil.runOnUiThread {
      // Policy is irrelevant for the key; DEFAULT resolves it like a view.
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

  // A disk cache that could not be written to is the only way these calls
  // fail. Android only: on iOS the removal is staged and cannot fail here.
  private fun settle(promise: Promise, failure: Throwable?) {
    if (failure == null) promise.resolve(null)
    else promise.reject("disk", failure.message ?: "Disk cache operation failed", failure)
  }

  // The module is going away (reload, or the host is destroyed): stop the
  // prefetches it started. Their promises are left unsettled on purpose; the
  // JS runtime they belong to is being torn down too.
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
