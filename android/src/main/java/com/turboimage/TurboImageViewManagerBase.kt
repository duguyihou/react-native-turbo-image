package  com.turboimage

import android.widget.ImageView
import android.widget.ImageView.ScaleType
import coil.Coil
import coil.drawable.CrossfadeDrawable
import coil.request.Disposable
import coil.request.ImageRequest
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

abstract class TurboImageViewManagerBase<T> : SimpleViewManager<T>() where T : ImageView {
  private lateinit var requestBuilder: ImageRequest.Builder
  private var disposable: Disposable? = null

  abstract fun getImageView(reactContext: ThemedReactContext): T

  override fun createViewInstance(p0: ThemedReactContext): T {
    val instance = getImageView(p0)
    requestBuilder = ImageRequest.Builder(p0).target { instance.setImageDrawable(it) }
      .listener(object : TurboImageListener<T>(instance) {})
    return instance
  }

  override fun onAfterUpdateTransaction(view: T) {
    super.onAfterUpdateTransaction(view)
    val request = requestBuilder.build()
    disposable = Coil.imageLoader(view.context).enqueue(request)
  }

  override fun onDropViewInstance(view: T) {
    super.onDropViewInstance(view)
    disposable?.let {
      if (!it.isDisposed) it.dispose()
    }
  }

  @ReactProp(name = "url")
  fun setSource(view: T, url: String) {
    requestBuilder.data(url)
  }

  @ReactProp(name = "resizeMode")
  fun setResizeMode(view: T, resizeMode: String?) {
    view.scaleType = RESIZE_MODE[resizeMode]
  }

  @ReactProp(name = "base64Placeholder")
  fun setBase64Placeholder(view: T, base64Placeholder: String?) {
    requestBuilder.placeholder(
      base64Placeholder?.let { TurboImageBase64.base64ToDrawable(view.context, it) }
    )
  }

  @ReactProp(name = "fadeDuration")
  fun setCrossfade(view: T, crossfade: Int = CrossfadeDrawable.DEFAULT_DURATION) {
    requestBuilder.crossfade(crossfade)
  }

  companion object {
    private val RESIZE_MODE = mapOf(
      "contain" to ScaleType.FIT_CENTER,
      "cover" to ScaleType.CENTER_CROP,
      "stretch" to ScaleType.FIT_XY,
      "center" to ScaleType.CENTER_INSIDE
    )
  }
}
