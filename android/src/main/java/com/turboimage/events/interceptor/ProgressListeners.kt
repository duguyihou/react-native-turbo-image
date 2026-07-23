package com.turboimage.events.interceptor

import java.util.concurrent.ConcurrentHashMap

/**
 * Maps React view tags to their [ProgressListener] so the shared
 * [ProgressInterceptor] can route download progress to the right view.
 * Entries are registered on every load and removed when the view is dropped.
 */
object ProgressListeners {
  private val listeners = ConcurrentHashMap<Int, ProgressListener>()

  fun register(viewTag: Int, listener: ProgressListener) {
    listeners[viewTag] = listener
  }

  fun unregister(viewTag: Int) {
    listeners.remove(viewTag)
  }

  fun get(viewTag: Int): ProgressListener? = listeners[viewTag]
}
