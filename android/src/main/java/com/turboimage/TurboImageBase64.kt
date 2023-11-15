package com.turboimage

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import kotlin.collections.HashMap

object TurboImageBase64 {
  private val cache = HashMap<String, Drawable>()

  fun base64ToDrawable(context: Context, base64: String): Drawable {
    if (cache.containsKey(base64)) {
      return cache[base64]!!
    }

    val bytes = Base64.decode(base64, Base64.DEFAULT)
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    val drawable = BitmapDrawable(context.resources, bitmap)

    cache[base64] = drawable

    return drawable
  }
}
