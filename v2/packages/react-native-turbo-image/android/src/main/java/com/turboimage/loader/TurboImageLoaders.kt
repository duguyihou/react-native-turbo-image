package com.turboimage.loader

import android.content.Context

/**
 * The process-wide loader adapter, shared by views and TurboImageModule.
 * Synchronised because `configureCache` runs on the JS thread.
 */
internal object TurboImageLoaders {
  private var adapter: ImageLoaderAdapter? = null
  private var cacheSizes = CacheSizes()

  /** Sets cache sizes. Coil can't resize caches, so false once the adapter exists. */
  @Synchronized
  fun configureCache(sizes: CacheSizes): Boolean {
    if (adapter != null) return false
    cacheSizes = sizes
    return true
  }

  /** The Coil adapter, created lazily (it needs a Context). */
  @Synchronized
  fun get(context: Context): ImageLoaderAdapter =
    adapter ?: CoilImageLoaderAdapter(context.applicationContext, cacheSizes).also { adapter = it }
}

/** Cache sizes in bytes; 0 keeps the adapter's default. */
internal data class CacheSizes(val maxDiskSize: Long = 0, val maxMemoryCost: Long = 0)
