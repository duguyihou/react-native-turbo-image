package com.turboimage.loader

import android.content.Context

/**
 * The process-wide loader adapter, shared by every view and by
 * TurboImageModule, so prefetches and evictions act on the caches views
 * read from. The counterpart of `TIImageLoaderRegistry.sharedLoader` on iOS.
 * Main thread only.
 *
 * Swapping Coil for another loader (RFC rule 1) means calling [set] with a
 * different [ImageLoaderAdapter]; nothing else changes.
 */
object TurboImageLoaders {
  private var adapter: ImageLoaderAdapter? = null

  /**
   * The adapter in use: the one given to [set], otherwise the bundled Coil
   * adapter, created on first use because it needs a Context.
   */
  fun get(context: Context): ImageLoaderAdapter =
    adapter ?: CoilImageLoaderAdapter(context.applicationContext).also { adapter = it }

  /**
   * Replaces the adapter for every view created and every cache-module call
   * made from now on. Call it before React Native starts (for example in
   * `Application.onCreate`): a view keeps the adapter it was created with,
   * so a later call leaves the views already on screen, and what they
   * cached, with the previous adapter.
   */
  fun set(adapter: ImageLoaderAdapter) {
    this.adapter = adapter
  }
}
