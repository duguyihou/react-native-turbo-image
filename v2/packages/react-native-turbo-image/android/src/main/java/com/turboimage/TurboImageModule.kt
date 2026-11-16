package com.turboimage

import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableType
import com.facebook.react.bridge.UiThreadUtil
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
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
  private fun resolve(sources: ReadableArray, index: Int, policy: TurboImageCore.CachePolicy): ResolvedRequest? {
    if (sources.getType(index) != ReadableType.Map) return null
    val source = sources.getMap(index) ?: return null
    val uri = if (source.hasKey("uri")) source.getString("uri").orEmpty() else ""
    val cacheKey = if (source.hasKey("cacheKey")) source.getString("cacheKey") else null
    return TurboImageCore.resolve(uri, cacheKey, policy) as? ResolvedRequest
  }

  override fun prefetch(sources: ReadableArray, cachePolicy: String, promise: Promise) {
    // The loader seam is main-thread only.
    UiThreadUtil.runOnUiThread {
      val loader = TurboImageLoaders.get(context)
      val policy = TurboImageCore.CachePolicy.fromJs(cachePolicy)
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
        val request = resolve(sources, i, policy)
        if (request == null) {
          finishOne(false)
          continue
        }
        var handle: LoadHandle? = null
        handle =
          loader.prefetch(request) { succeeded ->
            handle?.let { prefetches.remove(it) }
            finishOne(succeeded)
          }
        prefetches.add(handle)
      }
    }
  }

  override fun dispose(sources: ReadableArray, promise: Promise) {
    UiThreadUtil.runOnUiThread {
      val loader = TurboImageLoaders.get(context)
      for (i in 0 until sources.size()) {
        // Policy is irrelevant for the key; DEFAULT resolves it like a view.
        resolve(sources, i, TurboImageCore.CachePolicy.DEFAULT)?.let { loader.remove(it.cacheKey) }
      }
      promise.resolve(null)
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
      TurboImageLoaders.get(context).clearDiskCache()
      promise.resolve(null)
    }
  }

  companion object {
    const val NAME = "TurboImageModule"
  }
}
