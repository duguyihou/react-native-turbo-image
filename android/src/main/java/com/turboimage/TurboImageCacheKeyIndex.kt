package com.turboimage

import android.content.Context

/**
 * Tracks cache identity keys (cacheKey ?: uri) ever used by TurboImage, since
 * Coil's DiskCache exposes no cheap enumerate-by-prefix API - prefix-based
 * clearing needs its own index to know which keys exist.
 */
object TurboImageCacheKeyIndex {
  private const val PREFS_NAME = "TurboImageCacheKeyIndex"
  private const val KEY_SET = "keys"

  @Synchronized
  fun register(context: Context, key: String) {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val keys = HashSet(prefs.getStringSet(KEY_SET, emptySet()) ?: emptySet())
    if (keys.add(key)) {
      prefs.edit().putStringSet(KEY_SET, keys).apply()
    }
  }

  @Synchronized
  fun keys(context: Context, includePrefix: String?, excludePrefix: String?): List<String> {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val keys = prefs.getStringSet(KEY_SET, emptySet()) ?: emptySet()
    return keys.filter { key ->
      val included = includePrefix?.let { key.startsWith(it) } ?: true
      val excluded = excludePrefix?.let { key.startsWith(it) } ?: false
      included && !excluded
    }
  }

  @Synchronized
  fun remove(context: Context, keysToRemove: Collection<String>) {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val keys = HashSet(prefs.getStringSet(KEY_SET, emptySet()) ?: emptySet())
    keys.removeAll(keysToRemove.toSet())
    prefs.edit().putStringSet(KEY_SET, keys).apply()
  }

  @Synchronized
  fun clear(context: Context) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit().clear().apply()
  }
}
