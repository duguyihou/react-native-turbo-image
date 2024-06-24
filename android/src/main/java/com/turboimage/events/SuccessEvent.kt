package com.turboimage.events

import com.facebook.react.bridge.WritableMap
import com.facebook.react.uimanager.events.Event

class SuccessEvent(surfaceId: Int, viewId: Int, private val payload: WritableMap):
  Event<SuccessEvent>(surfaceId, viewId) {
  override fun getEventName(): String {
    return EVENT_NAME
  }

  override fun getEventData() = payload

  companion object {
    const val EVENT_NAME = "onSuccess"
  }
}
