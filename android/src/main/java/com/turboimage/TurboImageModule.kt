package com.turboimage

import coil.Coil
import coil.ImageLoader
import coil.annotation.ExperimentalCoilApi
import coil.request.ImageRequest
import com.facebook.react.bridge.*
import com.facebook.react.bridge.ReactContextBaseJavaModule
import okhttp3.Headers
import java.util.concurrent.ConcurrentHashMap

class TurboImageModule(private val context: ReactApplicationContext) :
  ReactContextBaseJavaModule(context) {
  // Same structure as TurboImageViewManager's shared loaders (#443): at most
  // one ImageLoader per cachePolicy, with the network observer disabled. A
  // loader built per prefetch call registers its own ConnectivityManager
  // network callback and never releases it, so frequent prefetching still
  // exhausts the 100-callback limit (fatal TooManyRequestsException).
  private val sharedLoaders = ConcurrentHashMap<Boolean, ImageLoader>()

  private fun sharedImageLoader(respectCacheHeaders: Boolean): ImageLoader {
    return sharedLoaders.getOrPut(respectCacheHeaders) {
      Coil.imageLoader(context.applicationContext)
        .newBuilder()
        .networkObserverEnabled(false)
        .respectCacheHeaders(respectCacheHeaders)
        .build()
    }
  }

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
    val imageLoader = sharedImageLoader(cachePolicy == "urlCache")
    imageRequests.forEach { imageRequest ->
      imageLoader.enqueue(imageRequest)
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
