package com.turboimage

import com.facebook.react.bridge.ReadableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.viewmanagers.TurboImageViewManagerDelegate
import com.facebook.react.viewmanagers.TurboImageViewManagerInterface
import com.turboimage.core.TurboImageCore
import com.turboimage.loader.CoilImageLoaderAdapter
import com.turboimage.loader.ImageLoaderAdapter

/**
 * Codegen-backed view manager. The delegate/interface pair is generated from
 * src/TurboImageViewNativeComponent.ts, so a prop added to the spec but not
 * implemented here is a compile error.
 */
@ReactModule(name = TurboImageViewManager.NAME)
class TurboImageViewManager :
  SimpleViewManager<TurboImageView>(), TurboImageViewManagerInterface<TurboImageView> {

  private val delegate = TurboImageViewManagerDelegate(this)

  // One adapter (and therefore one Coil ImageLoader and cache) per process.
  // Created lazily because it needs a Context.
  private var loader: ImageLoaderAdapter? = null

  override fun getDelegate(): ViewManagerDelegate<TurboImageView> = delegate

  override fun getName() = NAME

  override fun createViewInstance(context: ThemedReactContext): TurboImageView {
    val adapter = loader ?: CoilImageLoaderAdapter(context).also { loader = it }
    return TurboImageView(context, adapter)
  }

  override fun setSource(view: TurboImageView, value: ReadableMap?) {
    view.uri = value?.getString("uri")
    view.cacheKey = if (value?.hasKey("cacheKey") == true) value.getString("cacheKey") else null
  }

  override fun setCachePolicy(view: TurboImageView, value: String?) {
    view.cachePolicy = TurboImageCore.CachePolicy.fromJs(value)
  }

  override fun setResizeMode(view: TurboImageView, value: String?) {
    view.setResizeMode(value)
  }

  // Start at most one load per Fabric transaction, after all props landed.
  override fun onAfterUpdateTransaction(view: TurboImageView) {
    super.onAfterUpdateTransaction(view)
    view.maybeReload()
  }

  override fun onDropViewInstance(view: TurboImageView) {
    view.cancel()
    super.onDropViewInstance(view)
  }

  override fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> =
    mapOf(
      "topLoad" to mapOf("registrationName" to "onLoad"),
      "topError" to mapOf("registrationName" to "onError"),
    )

  companion object {
    const val NAME = "TurboImageView"
  }
}
