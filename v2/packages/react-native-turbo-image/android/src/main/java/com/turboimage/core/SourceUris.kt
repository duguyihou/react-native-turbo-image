package com.turboimage.core

import android.content.Context

/**
 * Turns a bare resource name (a `require()` asset in release builds) into an
 * `android.resource://` URI, as RN's ResourceDrawableIdHelper does. Anything
 * else, including unknown names, is returned unchanged for the core to judge.
 */
@android.annotation.SuppressLint("DiscouragedApi") // name lookup is the point
internal fun resolveSourceUri(context: Context, uri: String): String {
  if (uri.isEmpty() || uri.contains("://")) return uri
  // `getIdentifier` is slow and ids never change, so cache each name
  // (unknown ones as 0).
  val id =
    resourceIds.getOrPut(uri) {
      val name = uri.lowercase().replace("-", "_")
      val resources = context.resources
      resources.getIdentifier(name, "drawable", context.packageName).takeIf { it != 0 }
        ?: resources.getIdentifier(name, "raw", context.packageName)
    }
  return if (id != 0) "android.resource://${context.packageName}/$id" else uri
}

/** Resource id per bare name; one app package, so the name alone is the key. */
private val resourceIds = java.util.concurrent.ConcurrentHashMap<String, Int>()
