package com.turboimage.loader

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import okhttp3.Interceptor
import okhttp3.MediaType
import okhttp3.Response
import okhttp3.ResponseBody
import okio.Buffer
import okio.BufferedSource
import okio.ForwardingSource
import okio.buffer

/**
 * Routes OkHttp download progress to its load. Coil has no progress API, so
 * each request carries a per-load token header, stripped here.
 *
 * Known gap vs iOS: of deduplicated concurrent loads, only the leader gets
 * progress.
 */
internal class ProgressInterceptor : Interceptor {
  override fun intercept(chain: Interceptor.Chain): Response {
    val original = chain.request()
    val token = original.header(TOKEN_HEADER)?.toLongOrNull()
    val request =
      if (token != null) original.newBuilder().removeHeader(TOKEN_HEADER).build() else original
    val response = chain.proceed(request)
    val listener = token?.let { listeners[it] } ?: return response
    val body = response.body ?: return response
    return response.newBuilder().body(CountingBody(body, listener)).build()
  }

  /** Called on an OkHttp thread; implementations must hop threads themselves. */
  fun interface Listener {
    fun onBytes(completed: Long, total: Long)
  }

  // Not named `delegate`: that would clash with ForwardingSource.delegate.
  private class CountingBody(
    private val body: ResponseBody,
    private val listener: Listener,
  ) : ResponseBody() {
    private val source: BufferedSource by lazy {
      object : ForwardingSource(body.source()) {
          var completed = 0L

          override fun read(sink: Buffer, byteCount: Long): Long {
            val read = super.read(sink, byteCount)
            if (read > 0) {
              completed += read
              listener.onBytes(completed, body.contentLength())
            }
            return read
          }
        }
        .buffer()
    }

    override fun contentType(): MediaType? = body.contentType()

    override fun contentLength(): Long = body.contentLength()

    override fun source(): BufferedSource = source
  }

  companion object {
    const val TOKEN_HEADER = "X-TurboImage-Load"

    private val nextToken = AtomicLong(1)
    private val listeners = ConcurrentHashMap<Long, Listener>()

    /** Registers [listener] and returns the token to send with the request. */
    fun register(listener: Listener): Long =
      nextToken.getAndIncrement().also { listeners[it] = listener }

    fun unregister(token: Long) {
      listeners.remove(token)
    }
  }
}
