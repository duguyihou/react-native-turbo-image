package com.turboimage

import android.annotation.SuppressLint
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.graphics.drawable.RoundedBitmapDrawableFactory
import androidx.swiperefreshlayout.widget.CircularProgressDrawable
import coil.size.Size
import coil.transform.CircleCropTransformation
import coil.transform.RoundedCornersTransformation
import coil.transform.Transformation
import com.commit451.coiltransformations.BlurTransformation
import com.commit451.coiltransformations.ColorFilterTransformation
import com.facebook.react.uimanager.PixelUtil

import com.facebook.react.uimanager.ThemedReactContext

@SuppressLint("ViewConstructor")
class TurboImageView(private val reactContext: ThemedReactContext) :
  AppCompatImageView(reactContext) {
  var src: String? = null
  var cachePolicy: String? = "memory"
  var crossfade: Int? = null
  var blurhash: String? = null
  var indicator: HashMap<String, Any> = hashMapOf()

  var resize: Size? = null
  var borderRadius: Int? = null
  var rounded: Boolean? = null
  var blur: Int? = null
  var monochrome: Int? = null
  var tint: Int? = null

  var isSVG: Boolean? = null
  var isGif: Boolean? = null

  val blurhashDrawable: Drawable?
    get() {
      return blurhash?.let {
        borderRadius?.let { radii ->
         return drawRoundedBlurhash(this, it, radii)
        }
        drawBlurhash(this, it)
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

      borderRadius?.let {
        val radii = PixelUtil.toPixelFromDIP(it.toFloat())
        list.add(RoundedCornersTransformation(radii))
      }

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

  private fun drawBlurhash(view: TurboImageView, blurhash: String): Drawable {
    val bitmap = BlurHashDecoder.decode(blurhash, 8, 8)
    return BitmapDrawable(view.context.resources, bitmap)
  }

  private fun drawRoundedBlurhash(
    view: TurboImageView,
    blurhash: String,
    borderRadius: Int
  ): Drawable {
    val bitmap = BlurHashDecoder.decode(blurhash, 8, 8)
    return RoundedBitmapDrawableFactory.create(view.context.resources, bitmap).apply {
//      cornerRadius = PixelUtil.toPixelFromDIP(borderRadius.toFloat() / 60)
      cornerRadius = borderRadius.toFloat()
    }
  }
}
