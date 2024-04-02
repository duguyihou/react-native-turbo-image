package com.turboimage

import android.widget.ImageView
import coil.request.ErrorResult
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.common.MapBuilder
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.events.RCTEventEmitter

open class TurboImageListener<T>(private val view: T) : ImageRequest.Listener where T : ImageView {
  private val currentContext = view.context as ThemedReactContext
  private var eventEmitter: RCTEventEmitter = (view.context as ThemedReactContext).getJSModule(
    RCTEventEmitter::class.java
  )

  fun getExportedCustomDirectEventTypeConstants(): Map<String, Any> {
    return MapBuilder.of(
      ON_ERROR, MapBuilder.of("registrationName", ON_ERROR),
      ON_SUCCESS, MapBuilder.of("registrationName", ON_SUCCESS)
    )
  }

  override fun onError(request: ImageRequest, result: ErrorResult) {

    val payload = WritableNativeMap().apply {
      putString("error", result.toString())
    }
    eventEmitter.receiveEvent(view.id, ON_ERROR, payload)
  }

  override fun onSuccess(request: ImageRequest, result: SuccessResult) {
    val payload = WritableNativeMap().apply {
      putBoolean("isSampled", result.isSampled)
      putString("dataSource", result.dataSource.toString())
    }
    eventEmitter.receiveEvent(view.id, ON_SUCCESS, payload)
  }

  companion object {
    const val ON_ERROR = "onError"
    const val ON_SUCCESS = "onSuccess"
  }
}
