package com.turboimage.core

import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.ReadableType

/**
 * Reads `source.headers`. A malformed entry becomes an empty name so the core
 * fails the load rather than silently dropping, say, an auth header.
 */
internal fun readHeaders(source: ReadableMap?): List<Pair<String, String>> {
  if (source == null || !source.hasKey("headers") || source.getType("headers") != ReadableType.Array) {
    return emptyList()
  }
  val array = source.getArray("headers") ?: return emptyList()
  return (0 until array.size()).map { i ->
    val header = if (array.getType(i) == ReadableType.Map) array.getMap(i) else null
    fun field(key: String) =
      if (header?.hasKey(key) == true && header.getType(key) == ReadableType.String) header.getString(key).orEmpty() else ""
    field("name") to field("value")
  }
}
