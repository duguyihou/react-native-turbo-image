package com.turboimage

import android.graphics.Bitmap
import android.graphics.BlendMode
import android.graphics.BlendModeColorFilter
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.os.Build
import androidx.annotation.ColorInt
import androidx.core.graphics.createBitmap
import coil.size.Size
import coil.transform.Transformation

class MonochromeTransformation(
  @ColorInt private val color: Int
) : Transformation {

  override val cacheKey: String = "${MonochromeTransformation::class.java.name}-$color"

  override suspend fun transform(input: Bitmap, size: Size): Bitmap {
    val output = createBitmap(input.width, input.height, Bitmap.Config.ARGB_8888)

    val canvas = Canvas(output)
    val paint = Paint()
    paint.isAntiAlias = true
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      paint.colorFilter = BlendModeColorFilter(color, BlendMode.COLOR)
    } else {
      // TODO: custom color 
     val colorMatrix = ColorMatrix()
      colorMatrix.setSaturation(0.1F)
      paint.colorFilter = ColorMatrixColorFilter(colorMatrix)
    }
    canvas.drawBitmap(input, 0f, 0f, paint)

    return output
  }
}
