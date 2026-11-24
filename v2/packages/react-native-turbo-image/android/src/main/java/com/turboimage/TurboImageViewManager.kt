package com.turboimage

import com.facebook.react.bridge.ReadableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.TurboImageViewManagerInterface
import com.turboimage.core.CachePolicy
import com.turboimage.core.readHeaders
import com.turboimage.core.resolveSourceUri
import com.turboimage.loader.TurboImageLoaders

/** Codegen-backed view manager; an unimplemented spec prop is a compile error. */
@ReactModule(name = TurboImageViewManager.NAME)
class TurboImageViewManager :
  SimpleViewManager<TurboImageView>(), TurboImageViewManagerInterface<TurboImageView> {

  // The generated delegate, extended with the border style props.
  private val delegate = TurboImagePropsDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<TurboImageView> = delegate

  override fun getName() = NAME

  override fun createViewInstance(context: ThemedReactContext): TurboImageView {
    // One adapter per process, shared with TurboImageModule.
    return TurboImageView(context, TurboImageLoaders.get(context))
  }

  override fun setSource(view: TurboImageView, value: ReadableMap?) {
    view.request =
      view.request.copy(
        uri = value?.getString("uri")?.let { resolveSourceUri(view.context, it) }.orEmpty(),
        cacheKey = if (value?.hasKey("cacheKey") == true) value.getString("cacheKey") else null,
        headers = readHeaders(value),
      )
  }

  override fun setPlaceholder(view: TurboImageView, value: ReadableMap?) {
    view.blurhash = if (value?.hasKey("blurhash") == true) value.getString("blurhash") else null
    view.thumbhash = if (value?.hasKey("thumbhash") == true) value.getString("thumbhash") else null
    view.memoryCacheKey =
      if (value?.hasKey("memoryCacheKey") == true) value.getString("memoryCacheKey") else null
    // Resolved like a source (`require()` assets are resource names in release).
    view.placeholderUri =
      if (value?.hasKey("uri") == true) value.getString("uri")?.let { resolveSourceUri(view.context, it) } else null
  }

  override fun setRecyclingKey(view: TurboImageView, value: String?) {
    view.recyclingKey = value
  }

  override fun setShowPlaceholderOnFailure(view: TurboImageView, value: Boolean) {
    view.showPlaceholderOnFailure = value
  }

  override fun setFadeDuration(view: TurboImageView, value: Int) {
    view.fadeDuration = value
  }

  override fun setCachePolicy(view: TurboImageView, value: String?) {
    view.request = view.request.copy(cachePolicy = CachePolicy.fromJs(value))
  }

  override fun setResizeMode(view: TurboImageView, value: String?) {
    view.setResizeMode(value)
  }

  override fun setContentPositionX(view: TurboImageView, value: Double) {
    view.contentPositionX = value
  }

  override fun setContentPositionY(view: TurboImageView, value: Double) {
    view.contentPositionY = value
  }

  override fun setResize(view: TurboImageView, value: Double) {
    view.request = view.request.copy(processing = view.request.processing.copy(resize = value))
  }

  override fun setBlur(view: TurboImageView, value: Double) {
    view.request = view.request.copy(processing = view.request.processing.copy(blur = value))
  }

  override fun setMonochrome(view: TurboImageView, value: Int?) {
    view.request = view.request.copy(processing = view.request.processing.copy(monochrome = value))
  }

  override fun setTint(view: TurboImageView, value: Int?) {
    view.request = view.request.copy(processing = view.request.processing.copy(tint = value))
  }

  override fun setAllowHardware(view: TurboImageView, value: Boolean) {
    view.allowHardware = value
  }

  override fun setAllowDownscaling(view: TurboImageView, value: Boolean) {
    view.request = view.request.copy(allowDownscaling = value)
  }

  // iOS only (VisionKit Live Text).
  override fun setEnableLiveTextInteraction(view: TurboImageView, value: Boolean) = Unit

  override fun setProgressEnabled(view: TurboImageView, value: Boolean) {
    view.progressEnabled = value
  }

  override fun setLoadEventMask(view: TurboImageView, value: Int) {
    view.loadEventMask = value
  }

  // Fabric's content insets (border + padding); the base class drops them.
  // Applied as padding so the image fits inside the border, as on iOS.
  override fun setPadding(view: TurboImageView, left: Int, top: Int, right: Int, bottom: Int) {
    view.setPadding(left, top, right, bottom)
  }

  // Start at most one load per Fabric transaction, after all props landed.
  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    view.onTransactionEnd()
  }

  override fun onDropViewInstance(view: TurboImageView) {
    view.drop()
    super.onDropViewInstance(view)
  }

  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
    listOf("Start", "Progress", "Success", "Failure", "Completion").associate {
      "top$it" to mapOf("registrationName" to "on$it")
    }

  companion object {
    const val NAME = "TurboImageView"
  }
}
