package com.turboimage.events.interceptor

import okhttp3.ResponseBody
import okio.Buffer
import okio.BufferedSource
import okio.ForwardingSource
import okio.Source
import okio.buffer

class ProgressResponseBody(
  private val responseBody: ResponseBody,
  private val progressListener: ProgressListener
) : ResponseBody() {

  private val bufferedSource: BufferedSource by lazy {
    source(responseBody.source()).buffer()
  }

  override fun contentType() = responseBody.contentType()

  override fun contentLength() = responseBody.contentLength()

  override fun source(): BufferedSource = bufferedSource

  private fun source(source: Source): Source {
    return object : ForwardingSource(source) {
      var totalBytesRead = 0L

      override fun read(sink: Buffer, byteCount: Long): Long {
        val bytesRead = super.read(sink, byteCount)
        totalBytesRead += if (bytesRead != -1L) bytesRead else 0
        progressListener.update(totalBytesRead, responseBody.contentLength(), bytesRead == -1L)
        return bytesRead
      }
    }
  }
}
