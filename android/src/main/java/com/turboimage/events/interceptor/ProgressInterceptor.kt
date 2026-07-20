package com.turboimage.events.interceptor

import okhttp3.Interceptor
import okhttp3.Response

/**
 * Reports download progress for requests tagged with [VIEW_TAG_HEADER].
 *
 * The header carries the React view tag of the TurboImageView that issued
 * the request; it is stripped before the request goes to the network. The
 * matching [ProgressListener] is resolved through [ProgressListeners], which
 * lets a single shared OkHttpClient serve every view instead of building a
 * client (and a Coil ImageLoader) per image load.
 */
class ProgressInterceptor : Interceptor {
  override fun intercept(chain: Interceptor.Chain): Response {
    val originalRequest = chain.request()
    val viewTag = originalRequest.header(VIEW_TAG_HEADER)?.toIntOrNull()
    val request = if (viewTag != null) {
      originalRequest.newBuilder().removeHeader(VIEW_TAG_HEADER).build()
    } else {
      originalRequest
    }
    val response = chain.proceed(request)
    val listener = viewTag?.let { ProgressListeners.get(it) } ?: return response
    return response.newBuilder()
      .body(ProgressResponseBody(response.body!!, listener))
      .build()
  }

  companion object {
    const val VIEW_TAG_HEADER = "X-TurboImage-View-Tag"
  }
}
