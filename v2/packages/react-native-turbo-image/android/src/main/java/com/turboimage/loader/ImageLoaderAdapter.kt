package com.turboimage.loader

import android.content.res.Resources
import android.graphics.drawable.Drawable
import android.widget.ImageView
import com.turboimage.core.ResolvedRequest

/**
 * The Android loader seam, the counterpart of `TIImageLoading` on iOS.
 *
 * The view layer only knows this interface, so Coil stays a replaceable
 * adapter (RFC rule 1) and no Coil type appears in TurboImage's API.
 *
 * Contract:
 *  * [load] is called on the main thread.
 *  * Exactly one of [Listener.onSuccess]/[Listener.onError] fires, on the
 *    main thread, unless the handle is cancelled first, in which case none
 *    fire. [Listener.onProgress] may fire before that, never after it or
 *    after cancel, unthrottled (the view applies the core's throttle).
 *  * [LoadHandle.cancel] is idempotent and safe after completion.
 */
interface ImageLoaderAdapter {
  /**
   * How to decode and show one load. These are view-level choices, not part
   * of the request's identity, so they are not in [ResolvedRequest] and never
   * affect cache keys.
   *
   * @property fadeMillis cross-fade from the current drawable to the result;
   *   0 disables it. Adapters must skip it for memory-cache hits (the rule
   *   the iOS view applies too).
   * @property allowHardware false forces a software bitmap, for callers that
   *   read pixels or draw to a software canvas (e.g. shared-element
   *   transitions). Android-only; iOS has no equivalent distinction.
   */
  data class DisplayOptions(val fadeMillis: Int = 300, val allowHardware: Boolean = true)

  fun load(target: ImageView, request: ResolvedRequest, options: DisplayOptions, listener: Listener): LoadHandle

  // Cache management, backing TurboImageModule. Requests are resolved by the
  // core, like a view's, so views and the module agree on every key.

  /** Loads into the caches without a view; [onDone] once on the main thread. */
  fun prefetch(request: ResolvedRequest, onDone: (Boolean) -> Unit): LoadHandle

  /**
   * Evicts the images [requests] name from memory (every processed and sized
   * variant), from the key-addressed disk cache, and from the HTTP cache.
   * Only a request's `cacheKey` and `url` matter; its policy does not.
   *
   * Called on the main thread, but the disk work must not run there: Coil's
   * `DiskCache` writes its journal and deletes files in the calling thread.
   * Hence the callback, where iOS's `removeCachedImageForRequest:` simply
   * returns: Nuke's `DataCache` only stages a removal (hidden from reads at
   * once, deleted later on its own queue), so that call never blocks.
   * [onDone] fires once on the main thread: with null when everything is
   * gone, or with the I/O failure that stopped the disk work (the memory
   * entries are evicted either way). iOS has no such failure to report: a
   * staged removal cannot fail in the caller.
   */
  fun remove(requests: List<ResolvedRequest>, onDone: (Throwable?) -> Unit)

  fun clearMemoryCache()

  /**
   * Empties both disk stores: the key-addressed cache and the HTTP cache.
   * Same threading as [remove]: called on the main thread, works off it,
   * [onDone] once on the main thread, with the failure if there was one.
   */
  fun clearDiskCache(onDone: (Throwable?) -> Unit)

  /** Synchronous memory lookup for the `memoryCacheKey` placeholder. Main thread. */
  fun memoryCachedDrawable(cacheKey: String, resources: Resources): Drawable?

  interface Listener {
    /** Bytes received / expected; `total` <= 0 when unknown. */
    fun onProgress(completed: Long, total: Long)

    fun onSuccess(width: Int, height: Int)

    /**
     * @param code a `turboimage::LoadErrorCode` value; adapters classify
     *   their loader's errors so JS sees the same code on both platforms.
     * @param message diagnostic text only; not part of the contract.
     */
    fun onError(code: Int, message: String)
  }
}

fun interface LoadHandle {
  fun cancel()
}
