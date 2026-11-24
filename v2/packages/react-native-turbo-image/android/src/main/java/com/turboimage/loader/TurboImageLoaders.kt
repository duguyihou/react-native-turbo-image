package com.turboimage.loader

import android.content.Context

/**
 * The process-wide loader adapter, shared by every view and by
 * TurboImageModule, so prefetches and evictions act on the caches views
 * read from. The counterpart of `TIImageLoaderRegistry.sharedLoader` on iOS.
 * Synchronised: views and the module call it on the main thread, and
 * `configureCache` on the JS thread (a synchronous TurboModule method).
 */
internal object TurboImageLoaders {
  private var adapter: ImageLoaderAdapter? = null
  private var cacheSizes = CacheSizes()

  /**
   * `TurboImage.configureCache`: the sizes the bundled adapter's caches are
   * built with. Coil builds them once and cannot resize them, so this only
   * works before the adapter exists: false (and nothing changes) after the
   * first view or cache call.
   */
  @Synchronized
  fun configureCache(sizes: CacheSizes): Boolean {
    if (adapter != null) return false
    cacheSizes = sizes
    return true
  }

  /** The bundled Coil adapter, created on first use because it needs a Context. */
  @Synchronized
  fun get(context: Context): ImageLoaderAdapter =
    adapter ?: CoilImageLoaderAdapter(context.applicationContext, cacheSizes).also { adapter = it }
}

/** Cache sizes in bytes; 0 keeps the adapter's default. */
internal data class CacheSizes(val maxDiskSize: Long = 0, val maxMemoryCost: Long = 0)
