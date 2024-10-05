package com.turboimage.events.interceptor

interface ProgressListener {
  fun update(bytesRead: Long, contentLength: Long, done: Boolean)
}
