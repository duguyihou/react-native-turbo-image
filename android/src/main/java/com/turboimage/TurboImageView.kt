package com.turboimage

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.Base64
import androidx.appcompat.widget.AppCompatImageView
import androidx.swiperefreshlayout.widget.CircularProgressDrawable
import coil.size.Size
import coil.transform.CircleCropTransformation
import coil.transform.Transformation
import com.commit451.coiltransformations.BlurTransformation
import com.commit451.coiltransformations.ColorFilterTransformation

import com.facebook.react.uimanager.ThemedReactContext
import okhttp3.Headers

@SuppressLint("ViewConstructor")
class TurboImageView(private val reactContext: ThemedReactContext) :
  AppCompatImageView(reactContext) {
  var uri: String? = null
  var headers: Headers? = null
  var cacheKey: String? = null
  var cachePolicy: String? = "urlCache"
  var crossfade: Int? = null
  var blurhash: String? = null
  var thumbhash: String? = null
  var indicator: HashMap<String, Any> = hashMapOf()
  var showPlaceholderOnFailure: Boolean? = null

  var resize: Size? = null
  var rounded: Boolean? = null
  var blur: Int? = null
  var monochrome: Int? = null
  var tint: Int? = null
  var allowHardware: Boolean? = null

  var format: String? = null

  val blurhashDrawable: Drawable?
    get() {
      return blurhash?.let {
        drawBlurhash(this, it)
      }
    }

  val thumbhashDrawable: Drawable?
    get() {
      return thumbhash?.let {
        drawThumbhash(this, it)
      }
    }

  var memoryCacheKey: String? = null

  val circleProgressDrawable: CircularProgressDrawable?
    get() {
      indicator.let {
        when (it["style"]) {
          "medium" -> return CircularProgressDrawable(context).apply {
            setStyle(CircularProgressDrawable.DEFAULT)
            it["color"]?.let { color -> setColorSchemeColors(color as Int) }
          }

          "large" -> return CircularProgressDrawable(context).apply {
            setStyle(CircularProgressDrawable.LARGE)
            it["color"]?.let { color -> setColorSchemeColors(color as Int) }
          }

          else -> return null
        }
      }
    }

  val transformations: MutableList<Transformation>
    get() {
      val list = mutableListOf<Transformation>()

      rounded?.let {
        list.add(CircleCropTransformation())
      }

      blur?.let {
        list.add(BlurTransformation(reactContext, it.toFloat()))
      }

      monochrome?.let {
        list.add(MonochromeTransformation(it))
      }

      tint?.let {
        list.add(ColorFilterTransformation(it))
      }

      return list
    }

  private fun drawThumbhash(view: TurboImageView, hash: String): Drawable {
    val image = ThumbHash.thumbHashToRGBA(Base64.decode(hash, Base64.DEFAULT))

    // Guard against invalid dimensions
    val width = maxOf(image.width, 1)
    val height = maxOf(image.height, 1)

    val pixelCount = width * height
    val intArray = IntArray(pixelCount)

    // Only read as many pixels as actually exist
    val maxPixels = minOf(image.width * image.height, pixelCount)

    for (i in 0 until maxPixels) {
        val base = i * 4
        val r = image.rgba[base].toInt() and 0xFF
        val g = image.rgba[base + 1].toInt() and 0xFF
        val b = image.rgba[base + 2].toInt() and 0xFF
        val a = image.rgba[base + 3].toInt() and 0xFF

        intArray[i] =
            (a shl 24) or (r shl 16) or (g shl 8) or b
    }

    val bitmap = Bitmap.createBitmap(
        intArray,
        width,
        height,
        Bitmap.Config.ARGB_8888
    )

    return BitmapDrawable(view.context.resources, bitmap)
  }

  private fun drawBlurhash(view: TurboImageView, blurhash: String): Drawable {
    val bitmap = BlurHashDecoder.decode(blurhash, 8, 8)
    return BitmapDrawable(view.context.resources, bitmap)
  }
}
