package com.turboimage.events.interceptor

import okhttp3.Interceptor
import okhttp3.Response

class ProgressInterceptor(private val listener: ProgressListener) : Interceptor {
  override fun intercept(chain: Interceptor.Chain): Response {
    val originalResponse = chain.proceed(chain.request())
    return originalResponse.newBuilder()
      .body(ProgressResponseBody(originalResponse.body!!, listener))
      .build()
  }
}
