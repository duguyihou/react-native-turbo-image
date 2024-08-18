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
    val intArray = IntArray(image.width * image.height)
    for (i in intArray.indices) {
      val r = image.rgba[i * 4].toInt() and 0xFF
      val g = image.rgba[i * 4 + 1].toInt() and 0xFF
      val b = image.rgba[i * 4 + 2].toInt() and 0xFF
      val a = image.rgba[i * 4 + 3].toInt() and 0xFF
      intArray[i] =
        ((a and 0xff) shl 24) or ((r and 0xff) shl 16) or ((g and 0xff) shl 8) or (b and 0xff)
    }
    val bitmap = Bitmap.createBitmap(intArray, image.width, image.height, Bitmap.Config.ARGB_8888)
    return BitmapDrawable(view.context.resources, bitmap)
  }

  private fun drawBlurhash(view: TurboImageView, blurhash: String): Drawable {
    val bitmap = BlurHashDecoder.decode(blurhash, 8, 8)
    return BitmapDrawable(view.context.resources, bitmap)
  }
}
