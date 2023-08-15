package  com.turboimage

import android.widget.ImageView
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
}
