package com.turboimage

import android.view.View
import com.facebook.react.bridge.ColorPropConverter
import com.facebook.react.bridge.DynamicFromObject
import com.facebook.react.uimanager.BackgroundStyleApplicator
import com.facebook.react.uimanager.LengthPercentage
import com.facebook.react.uimanager.style.BorderRadiusProp
import com.facebook.react.uimanager.style.BorderStyle
import com.facebook.react.uimanager.style.LogicalEdge

/**
 * The border style props (`borderWidth`, `borderColor`, `borderRadius`,
 * `borderStyle` and their per-edge and per-corner forms) for
 * [TurboImageView].
 *
 * Why this exists: on iOS every Fabric view draws its border in the base
 * class. On Android only React Native's own view managers do. A codegen
 * manager gets the radius props as a logged "unsupported" warning and never
 * sees width, colour or style at all, so `<TurboImage style={{borderWidth}}>`
 * drew a border on iOS and nothing on Android.
 *
 * The drawing is React Native's own: `BackgroundStyleApplicator` puts the
 * border in the view's background, exactly as `ReactImageManager` does for
 * `<Image>`. [TurboImageView.onDraw] then clips the image to the inside of
 * that border, so the border is not painted over and rounded corners cut the
 * image (and the placeholder, which is drawn the same way).
 */
internal object TurboImageBorders {

  private val widths =
    mapOf(
      "borderWidth" to LogicalEdge.ALL,
      "borderLeftWidth" to LogicalEdge.LEFT,
      "borderRightWidth" to LogicalEdge.RIGHT,
      "borderTopWidth" to LogicalEdge.TOP,
      "borderBottomWidth" to LogicalEdge.BOTTOM,
      "borderStartWidth" to LogicalEdge.START,
      "borderEndWidth" to LogicalEdge.END,
    )

  private val colors =
    mapOf(
      "borderColor" to LogicalEdge.ALL,
      "borderLeftColor" to LogicalEdge.LEFT,
      "borderRightColor" to LogicalEdge.RIGHT,
      "borderTopColor" to LogicalEdge.TOP,
      "borderBottomColor" to LogicalEdge.BOTTOM,
      "borderStartColor" to LogicalEdge.START,
      "borderEndColor" to LogicalEdge.END,
      "borderBlockColor" to LogicalEdge.BLOCK,
      "borderBlockEndColor" to LogicalEdge.BLOCK_END,
      "borderBlockStartColor" to LogicalEdge.BLOCK_START,
    )

  private val radii =
    mapOf(
      "borderRadius" to BorderRadiusProp.BORDER_RADIUS,
      "borderTopLeftRadius" to BorderRadiusProp.BORDER_TOP_LEFT_RADIUS,
      "borderTopRightRadius" to BorderRadiusProp.BORDER_TOP_RIGHT_RADIUS,
      "borderBottomRightRadius" to BorderRadiusProp.BORDER_BOTTOM_RIGHT_RADIUS,
      "borderBottomLeftRadius" to BorderRadiusProp.BORDER_BOTTOM_LEFT_RADIUS,
      "borderTopStartRadius" to BorderRadiusProp.BORDER_TOP_START_RADIUS,
      "borderTopEndRadius" to BorderRadiusProp.BORDER_TOP_END_RADIUS,
      "borderBottomStartRadius" to BorderRadiusProp.BORDER_BOTTOM_START_RADIUS,
      "borderBottomEndRadius" to BorderRadiusProp.BORDER_BOTTOM_END_RADIUS,
      "borderEndEndRadius" to BorderRadiusProp.BORDER_END_END_RADIUS,
      "borderEndStartRadius" to BorderRadiusProp.BORDER_END_START_RADIUS,
      "borderStartEndRadius" to BorderRadiusProp.BORDER_START_END_RADIUS,
      "borderStartStartRadius" to BorderRadiusProp.BORDER_START_START_RADIUS,
    )

  /**
   * Applies [propName] to [view] if it is a border prop. Returns false for
   * any other prop, which the caller then handles as before.
   *
   * [value] is what Fabric hands a view manager delegate: a `Double` for a
   * number, a `String` for a percentage radius or a style name, a processed
   * colour for a colour, and null when the prop was removed.
   */
  @JvmStatic
  fun apply(view: View, propName: String, value: Any?): Boolean {
    widths[propName]?.let { edge ->
      BackgroundStyleApplicator.setBorderWidth(view, edge, (value as? Number)?.toFloat())
      // The clip in onDraw follows the border width, and changing a
      // background drawable's insets does not redraw the image by itself.
      view.invalidate()
      return true
    }
    colors[propName]?.let { edge ->
      BackgroundStyleApplicator.setBorderColor(
        view, edge, ColorPropConverter.getColor(value, view.context))
      return true
    }
    radii[propName]?.let { corner ->
      // Same conversion as ReactImageManager: a number is in dp, a string a
      // percentage, anything else (null included) removes the radius.
      val radius = value?.let { LengthPercentage.setFromDynamic(DynamicFromObject(it)) }
      BackgroundStyleApplicator.setBorderRadius(view, corner, radius)
      view.invalidate()
      return true
    }
    if (propName == "borderStyle") {
      BackgroundStyleApplicator.setBorderStyle(
        view, (value as? String)?.let { BorderStyle.fromString(it) })
      return true
    }
    return false
  }
}
