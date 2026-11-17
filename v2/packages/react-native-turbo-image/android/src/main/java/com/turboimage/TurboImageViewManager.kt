package com.turboimage

import com.facebook.react.bridge.ReadableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.TurboImageViewManagerDelegate
import com.facebook.react.viewmanagers.TurboImageViewManagerInterface
import com.turboimage.core.TurboImageCore
import com.turboimage.core.readHeaders
import com.turboimage.core.resolveSourceUri
import com.turboimage.loader.TurboImageLoaders

/**
 * Codegen-backed view manager. The delegate/interface pair is generated from
 * src/TurboImageViewNativeComponent.ts, so a prop added to the spec but not
 * implemented here is a compile error.
 */
@ReactModule(name = TurboImageViewManager.NAME)
class TurboImageViewManager :
  SimpleViewManager<TurboImageView>(), TurboImageViewManagerInterface<TurboImageView> {

  private val delegate = TurboImageViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<TurboImageView> = delegate

  override fun getName() = NAME

  override fun createViewInstance(context: ThemedReactContext): TurboImageView {
    // One adapter (one Coil ImageLoader and cache) per process, shared with
    // TurboImageModule.
    return TurboImageView(context, TurboImageLoaders.get(context))
  }

  override fun setSource(view: TurboImageView, value: ReadableMap?) {
    view.uri = value?.getString("uri")?.let { resolveSourceUri(view.context, it) }
    view.cacheKey = if (value?.hasKey("cacheKey") == true) value.getString("cacheKey") else null
    view.headers = readHeaders(value)
  }

  override fun setPlaceholder(view: TurboImageView, value: ReadableMap?) {
    view.blurhash = if (value?.hasKey("blurhash") == true) value.getString("blurhash") else null
    view.thumbhash = if (value?.hasKey("thumbhash") == true) value.getString("thumbhash") else null
    view.memoryCacheKey =
      if (value?.hasKey("memoryCacheKey") == true) value.getString("memoryCacheKey") else null
  }

  override fun setShowPlaceholderOnFailure(view: TurboImageView, value: Boolean) {
    view.showPlaceholderOnFailure = value
  }

  override fun setFadeDuration(view: TurboImageView, value: Int) {
    view.fadeDuration = value
  }

  override fun setCachePolicy(view: TurboImageView, value: String?) {
    view.cachePolicy = TurboImageCore.CachePolicy.fromJs(value)
  }

  override fun setResizeMode(view: TurboImageView, value: String?) {
    view.setResizeMode(value)
  }

  override fun setResize(view: TurboImageView, value: Double) {
    view.processing = view.processing.copy(resize = value)
  }

  override fun setBlur(view: TurboImageView, value: Double) {
    view.processing = view.processing.copy(blur = value)
  }

  override fun setMonochrome(view: TurboImageView, value: Int?) {
    view.processing = view.processing.copy(monochrome = value)
  }

  override fun setTint(view: TurboImageView, value: Int?) {
    view.processing = view.processing.copy(tint = value)
  }

  // iOS-only (VisionKit Live Text). Android has no equivalent system
  // interaction, and 1.x ignored the prop there too.
  override fun setEnableLiveTextInteraction(view: TurboImageView, value: Boolean) = Unit

  // Start at most one load per Fabric transaction, after all props landed.
  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    view.onTransactionEnd()
  }

  override fun onDropViewInstance(view: TurboImageView) {
    view.cancel()
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
