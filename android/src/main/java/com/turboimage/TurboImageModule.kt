package com.turboimage

import coil.Coil
import coil.ImageLoader
import coil.annotation.ExperimentalCoilApi
import coil.request.ImageRequest
import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule
import okhttp3.Headers

class TurboImageModule(private val context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {
  private var imageLoader: ImageLoader? = null

  override fun getName(): String = REACT_CLASS

  @ReactMethod
  fun prefetch(sources: ReadableArray, cachePolicy: String, promise: Promise) {
    var completedRequestCount = 0
    fun handleRequestCount() {
      completedRequestCount++
      if (sources.size() == completedRequestCount) {
        promise.resolve(true)
      }
    }

    val imageRequests = sources.toArrayList().map { source ->
      val uri = (source as HashMap<*, *>)["uri"] as String
      val headers = source["headers"] as? HashMap<*, *>

      if (headers != null) {
        val headersBuilder = Headers.Builder()
        headers.map { (key, value) ->
          headersBuilder.add(key as String, value as String)
        }
        ImageRequest.Builder(context)
          .headers(headersBuilder.build())
          .data(uri)
          .listener(
            onSuccess = { _, _ -> handleRequestCount() },
            onError = { _, _ -> handleRequestCount() }
          )
          .build()
      } else {
        ImageRequest.Builder(context)
          .data(uri)
          .listener(
            onSuccess = { _, _ -> handleRequestCount() },
            onError = { _, _ -> handleRequestCount() }
          )
          .build()
      }
    }
    imageLoader = Coil.imageLoader(context).newBuilder()
      .respectCacheHeaders(cachePolicy == "urlCache")
      .build()
    imageRequests.forEach { imageRequest ->
      imageLoader?.enqueue(imageRequest)
    }
  }

  @ReactMethod
  fun clearMemoryCache(promise: Promise) {
    Coil.imageLoader(context).memoryCache?.clear()
    promise.resolve("Success")
  }

  @OptIn(ExperimentalCoilApi::class)
  @ReactMethod
  fun clearDiskCache(promise: Promise) {
    Coil.imageLoader(context).diskCache?.clear()
    promise.resolve("Success")
  }


  companion object {
    private const val REACT_CLASS = "TurboImageViewManager"
  }
}
