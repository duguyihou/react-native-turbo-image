package com.turboimage

import coil.request.ErrorResult
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.facebook.react.bridge.ReactContext
import com.facebook.react.bridge.WritableNativeMap
import com.facebook.react.uimanager.events.RCTEventEmitter

class TurboImageListener(private val view: TurboImageView) : ImageRequest.Listener {

  override fun onStart(request: ImageRequest) {
    super.onStart(request)
    val payload = WritableNativeMap().apply {
      putString("state", "running")
    }
    val reactContext = view.context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java)
      .receiveEvent(view.id, "onStart", payload)
  }

  override fun onSuccess(request: ImageRequest, result: SuccessResult) {
    super.onSuccess(request, result)
    val successPayload = WritableNativeMap().apply {
      putInt("width", result.drawable.intrinsicWidth)
      putInt("height", result.drawable.intrinsicHeight)
      putString("source", request.data.toString())
    }
    val reactContext = view.context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java)
      .receiveEvent(view.id, "onSuccess", successPayload)
    val completionPayload = WritableNativeMap().apply {
      putString("state", "completed")
    }
    reactContext.getJSModule(RCTEventEmitter::class.java)
      .receiveEvent(view.id, "onCompletion", completionPayload)
  }

  override fun onError(request: ImageRequest, result: ErrorResult) {
    super.onError(request, result)
    val failurePayload = WritableNativeMap().apply {
      putString("error", result.throwable.message)
    }
    val reactContext = view.context as ReactContext
    reactContext.getJSModule(RCTEventEmitter::class.java)
      .receiveEvent(view.id, "onFailure", failurePayload)
    val completionPayload = WritableNativeMap().apply {
      putString("state", "completed")
    }
    reactContext.getJSModule(RCTEventEmitter::class.java)
      .receiveEvent(view.id, "onCompletion", completionPayload)
  }
}
