package com.turboimage.core

import android.content.Context

/**
 * Android release builds resolve `require('./logo.png')` to a bare resource
 * name (`src_assets_logo`), not a URI: React Native packages bundled images
 * as drawables. This turns such a name into the `android.resource://` URI
 * the core accepts and Coil loads. Everything with a scheme is returned
 * unchanged for the core to validate. An unknown name is returned as is, so
 * the core rejects it (`invalidRequest`) instead of the load silently
 * showing nothing.
 *
 * The naming rule matches RN's ResourceDrawableIdHelper: lower-case, `-`
 * becomes `_`, and drawables are tried before raw resources.
 */
@android.annotation.SuppressLint("DiscouragedApi") // name lookup is the point
internal fun resolveSourceUri(context: Context, uri: String): String {
  if (uri.isEmpty() || uri.contains("://")) return uri
  val name = uri.lowercase().replace("-", "_")
  val resources = context.resources
  val id =
    resources.getIdentifier(name, "drawable", context.packageName).takeIf { it != 0 }
      ?: resources.getIdentifier(name, "raw", context.packageName)
  return if (id != 0) "android.resource://${context.packageName}/$id" else uri
}
