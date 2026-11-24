package com.turboimage.loader

import android.content.res.Resources
import android.graphics.drawable.Drawable
import android.widget.ImageView
import com.turboimage.core.ResolvedRequest

/**
 * The Android loader seam (internal, ADR 0014; counterpart of iOS's
 * `TIImageLoading`). Unlike iOS (ADR 0004), the adapter gets the `ImageView`
 * and paints, fades and animates the result itself, so it must never touch
 * the view after [LoadHandle.cancel].
 *
 * Contract:
 *  * [load] is called on the main thread.
 *  * Exactly one of [Listener.onSuccess]/[Listener.onError] fires, on the main
 *    thread, unless cancelled first. [Listener.onProgress] fires only before
 *    that, unthrottled.
 *  * [LoadHandle.cancel] is idempotent and safe after completion.
 */
internal interface ImageLoaderAdapter {
  /**
   * View-level display choices; never part of cache keys.
   *
   * @property fadeMillis cross-fade duration; 0 disables it. Skipped for
   *   memory-cache hits.
   * @property allowHardware false forces a software bitmap.
   * @property reportProgress false when nothing listens; adapters need not
   *   call [Listener.onProgress].
   */
  data class DisplayOptions(
    val fadeMillis: Int = 300,
    val allowHardware: Boolean = true,
    val reportProgress: Boolean = true,
  )

  fun load(target: ImageView, request: ResolvedRequest, options: DisplayOptions, listener: Listener): LoadHandle

  // Cache management, backing TurboImageModule.

  /**
   * Loads `placeholder.uri` like [load], sized for [sizeOf], but never touches
   * the view. [onDone] fires once on the main thread (null on failure),
   * unless cancelled first.
   */
  fun loadPlaceholder(sizeOf: ImageView, request: ResolvedRequest, onDone: (Drawable?) -> Unit): LoadHandle

  /**
   * `TurboImage.getSize`: caches [request] like [prefetch] and reports its
   * oriented pixel size, ideally from the header. Exactly one callback, on
   * the main thread, unless cancelled first.
   */
  fun imageSize(
    request: ResolvedRequest,
    onSize: (width: Int, height: Int) -> Unit,
    onError: (code: Int, message: String) -> Unit,
  ): LoadHandle

  /**
   * Loads into the caches; [onDone] once on the main thread. With
   * `memoryWrite` off, store the bytes without decoding.
   */
  fun prefetch(request: ResolvedRequest, onDone: (Boolean) -> Unit): LoadHandle

  /**
   * Evicts [requests] (all variants) from memory, the disk cache and the
   * HTTP cache, by `cacheKey` and `url`. Called on the main thread; disk work
   * must run off it (Coil's `DiskCache` blocks). [onDone] once on the main
   * thread with null, or the I/O failure.
   */
  fun remove(requests: List<ResolvedRequest>, onDone: (Throwable?) -> Unit)

  fun clearMemoryCache()

  /** Empties the disk cache and the HTTP cache. Same threading as [remove]. */
  fun clearDiskCache(onDone: (Throwable?) -> Unit)

  /** Synchronous memory lookup for the `memoryCacheKey` placeholder. Main thread. */
  fun memoryCachedDrawable(cacheKey: String, resources: Resources): Drawable?

  interface Listener {
    /** Bytes received / expected; `total` <= 0 when unknown. */
    fun onProgress(completed: Long, total: Long)

    /** `animated`: the image plays (GIF, APNG, animated WebP). */
    fun onSuccess(width: Int, height: Int, animated: Boolean)

    /**
     * @param code a `turboimage::LoadErrorCode` value.
     * @param message diagnostic text only.
     */
    fun onError(code: Int, message: String)
  }
}

internal fun interface LoadHandle {
  fun cancel()
}
