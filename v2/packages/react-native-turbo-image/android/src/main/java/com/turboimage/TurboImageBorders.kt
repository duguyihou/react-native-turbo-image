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
 * Border style props for [TurboImageView]. On Android, codegen view managers
 * never receive them, so we apply them via `BackgroundStyleApplicator` like
 * `ReactImageManager`; [TurboImageView.onDraw] clips the image inside.
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

  /** Applies [propName] if it is a border prop; returns false otherwise. */
  @JvmStatic
  fun apply(view: View, propName: String, value: Any?): Boolean {
    widths[propName]?.let { edge ->
      BackgroundStyleApplicator.setBorderWidth(view, edge, (value as? Number)?.toFloat())
      // The onDraw clip depends on the width; force a redraw.
      view.invalidate()
      return true
    }
    colors[propName]?.let { edge ->
      BackgroundStyleApplicator.setBorderColor(
        view, edge, ColorPropConverter.getColor(value, view.context))
      return true
    }
    radii[propName]?.let { corner ->
      // As ReactImageManager: number = dp, string = percentage, else removed.
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
