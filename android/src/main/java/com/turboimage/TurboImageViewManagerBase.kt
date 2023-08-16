package  com.turboimage

import android.widget.ImageView
import android.widget.ImageView.ScaleType
import coil.Coil
import coil.request.Disposable
import coil.request.ImageRequest
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp

abstract class TurboImageViewManagerBase<T>: SimpleViewManager<T>() where T: ImageView {
  private lateinit var requestBuilder: ImageRequest.Builder
  private var disposable: Disposable? = null

  abstract fun getImageView(reactContext: ThemedReactContext): T

  override fun createViewInstance(p0: ThemedReactContext): T {
    val instance = getImageView(p0)
    requestBuilder = ImageRequest.Builder(p0).target { instance.setImageDrawable(it) }
    return instance
  }

  override fun onAfterUpdateTransaction(view: T) {
    super.onAfterUpdateTransaction(view)
    disposable = Coil.imageLoader(view.context).enqueue(requestBuilder.build())
  }

  override fun onDropViewInstance(view: T) {
    super.onDropViewInstance(view)
    disposable?.let {
      if (!it.isDisposed) it.dispose()
    }
  }

  @ReactProp(name ="source")
  fun setSource(view: T, source: ReadableMap?) {
    if (source != null && source.hasKey("uri")) {
      requestBuilder.data(source.getString("uri"))
    } else {
      requestBuilder.data(null)
    }
  }

  @ReactProp(name="resizeMode")
  fun setResizeMode(view: T, resizeMode: String?) {
    view.scaleType = RESIZE_MODE[resizeMode]
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
