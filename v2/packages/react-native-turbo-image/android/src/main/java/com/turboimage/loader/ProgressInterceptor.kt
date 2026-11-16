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
 * Routes OkHttp download progress to the load that issued the request.
 *
 * Coil has no progress API, so the adapter tags each request with a
 * per-load token header; this interceptor strips it before the request
 * leaves the device, and wraps the response body to count bytes.
 *
 * A token per *load* rather than per view (1.x used the view tag): a view
 * that switched `source` while its old request is still downloading must not
 * receive the old request's progress.
 *
 * Known gap vs iOS: with DeDupeConcurrentRequestStrategy only the leading
 * request of N identical concurrent loads reaches the network, so the
 * followers get no progress (they complete from the disk cache). Nuke's
 * coalescing forwards progress to every subscriber.
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

  // `body`, not `delegate`: inside the ForwardingSource below, `delegate`
  // would resolve to ForwardingSource.delegate (the okio Source).
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
