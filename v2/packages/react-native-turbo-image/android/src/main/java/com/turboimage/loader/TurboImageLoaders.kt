package com.turboimage.loader

import android.content.Context

/**
 * The process-wide loader adapter, shared by every view and by
 * TurboImageModule, so prefetches and evictions act on the caches views
 * read from. Created lazily because it needs a Context. Main thread only.
 *
 * Swapping Coil for another loader (RFC rule 1) means providing a different
 * [ImageLoaderAdapter] here; nothing else changes.
 */
object TurboImageLoaders {
  private var adapter: ImageLoaderAdapter? = null

  fun get(context: Context): ImageLoaderAdapter =
    adapter ?: CoilImageLoaderAdapter(context.applicationContext).also { adapter = it }
}
