package com.turboimage

import coil.request.ErrorResult
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.ReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.turboimage.events.CompletionEvent
import com.turboimage.events.FailureEvent
import com.turboimage.events.StartEvent
import com.turboimage.events.SuccessEvent

class TurboImageListener(private val view: TurboImageView) : ImageRequest.Listener {

  override fun onStart(request: ImageRequest) {
    super.onStart(request)

    val reactContext = view.context as ReactContext
    UIManagerHelper.getEventDispatcher(reactContext, view.id)?.let {
      val payload = Arguments.createMap().apply {
        putString("state", "running")
      }
      val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
      it.dispatchEvent(StartEvent(surfaceId, view.id, payload))
    }
  }

  override fun onSuccess(request: ImageRequest, result: SuccessResult) {
    super.onSuccess(request, result)

    val reactContext = view.context as ReactContext
    UIManagerHelper.getEventDispatcher(reactContext, view.id)?.let {
      val payload = Arguments.createMap().apply {
        putInt("width", result.drawable.intrinsicWidth)
        putInt("height", result.drawable.intrinsicHeight)
        putString("source", request.data.toString())
      }
      val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
      it.dispatchEvent(SuccessEvent(surfaceId, view.id, payload))
    }

    UIManagerHelper.getEventDispatcher(reactContext, view.id)?.let {
      val payload = Arguments.createMap().apply {
        putString("state", "completed")
      }
      val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
      it.dispatchEvent(CompletionEvent(surfaceId, view.id, payload))
    }
  }

  override fun onError(request: ImageRequest, result: ErrorResult) {
    super.onError(request, result)

    val reactContext = view.context as ReactContext
    UIManagerHelper.getEventDispatcher(reactContext, view.id)?.let {
      val payload = Arguments.createMap().apply {
        putString("error", result.throwable.message)
      }
      val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
      it.dispatchEvent(FailureEvent(surfaceId, view.id, payload))
    }

    UIManagerHelper.getEventDispatcher(reactContext, view.id)?.let {
      val payload = Arguments.createMap().apply {
        putString("state", "completed")
      }
      val surfaceId = UIManagerHelper.getSurfaceId(reactContext)
      it.dispatchEvent(CompletionEvent(surfaceId, view.id, payload))
    }
  }
}
