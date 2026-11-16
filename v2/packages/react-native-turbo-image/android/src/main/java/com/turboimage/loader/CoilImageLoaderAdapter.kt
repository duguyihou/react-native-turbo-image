package com.turboimage.loader

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.ImageView
import coil3.Image
import coil3.ImageLoader
import coil3.annotation.ExperimentalCoilApi
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.CacheStrategy
import coil3.network.DeDupeConcurrentRequestStrategy
import coil3.network.HttpException
import coil3.network.NetworkHeaders
import coil3.network.httpHeaders
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import coil3.target.ImageViewTarget
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath

/**
 * Coil 3 adapter. Everything Coil-specific lives in this file.
 *
 * Cross-platform cache contract (RFC rule 3, mirrored in NukeImageLoader.swift):
 *  * the disk tier is TurboImage's own Coil DiskCache of original bytes, the
 *    same size as Nuke's DataCache,
 *  * HTTP caching is off: OkHttp gets no `Cache`, and Coil's
 *    `CacheStrategy.DEFAULT` serves disk hits without consulting
 *    `Cache-Control`, which matches Nuke's `withDataCache` (`urlCache = nil`),
 *  * concurrent requests for the same cache key are de-duplicated, which
 *    matches Nuke's default task coalescing.
 */
/**
 * A Coil ImageView target that only ever sets the *loaded* image. Coil's
 * default target sets the request's placeholder on start and its error
 * image on failure; both are null for us, so it would wipe the TurboImage
 * placeholder the view already shows. iOS keeps the placeholder on start and
 * on failure, so Android must too (RFC rule 3). Subclassing (rather than a
 * plain Target) keeps Coil's view-lifecycle handling: detach/attach
 * cancel/restart, see RFC open question 1.
 */
private class KeepCurrentImageTarget(view: ImageView) : ImageViewTarget(view) {
  override fun onStart(placeholder: Image?) = Unit

  override fun onError(error: Image?) = Unit
}

class CoilImageLoaderAdapter(context: Context) : ImageLoaderAdapter {
  private val imageLoader: ImageLoader = buildImageLoader(context.applicationContext)

  override fun load(
    target: ImageView,
    request: ResolvedRequest,
    listener: ImageLoaderAdapter.Listener,
  ): LoadHandle {
    // `finished` enforces the seam contract on the main thread: no progress
    // after success/failure/cancel. Progress arrives on OkHttp threads and is
    // posted to main, where this flag is checked.
    var finished = false
    val token =
      ProgressInterceptor.register { completed, total ->
        mainHandler.post { if (!finished) listener.onProgress(completed, total) }
      }
    fun finish() {
      finished = true
      ProgressInterceptor.unregister(token)
    }

    // Mechanical translation only; the C++ core already decided policy.
    val coilRequest =
      ImageRequest.Builder(target.context)
        .data(request.url)
        .memoryCacheKey(request.cacheKey)
        .diskCacheKey(request.cacheKey)
        .memoryCachePolicy(tierPolicy(request.memoryRead, request.memoryWrite))
        .diskCachePolicy(tierPolicy(request.diskRead, request.diskWrite))
        .networkCachePolicy(if (request.allowNetwork) CachePolicy.ENABLED else CachePolicy.DISABLED)
        .httpHeaders(NetworkHeaders.Builder().set(ProgressInterceptor.TOKEN_HEADER, token.toString()).build())
        .target(KeepCurrentImageTarget(target))
        .listener(
          onSuccess = { _, result ->
            finish()
            listener.onSuccess(result.image.width, result.image.height)
          },
          onError = { _, result ->
            finish()
            listener.onError(classify(result.throwable, request), result.throwable.message ?: "Unknown error")
          },
          onCancel = { finish() },
        )
        .build()

    val disposable = imageLoader.enqueue(coilRequest)
    // `dispose()` cancels the job and clears the ViewTarget, so no listener
    // fires afterwards (RFC §Open questions 1).
    return LoadHandle {
      finish()
      disposable.dispose()
    }
  }

  /**
   * Maps Coil failures onto `turboimage::LoadErrorCode`. Must stay in step
   * with `NukeImageLoader.classify` on iOS.
   *
   * With network reads disabled Coil asks OkHttp for `only-if-cached`, and
   * our cache-less client answers with a synthetic HTTP 504. Coil does the
   * same when the device is offline, so a 504 only means "not cached" when
   * the *policy* forbade the network; otherwise it is a network failure.
   *
   * Anything that is not a transport failure happened after bytes arrived
   * (fetchers are chosen by the core-validated http(s) scheme), so it is
   * classified as a decode failure.
   */
  private fun classify(error: Throwable, request: ResolvedRequest): Int =
    when {
      error is HttpException && error.response.code == 504 && !request.allowNetwork ->
        TurboImageCore.LoadErrorCode.NOT_CACHED.nativeValue
      error is HttpException || error is IOException -> TurboImageCore.LoadErrorCode.NETWORK.nativeValue
      else -> TurboImageCore.LoadErrorCode.DECODE.nativeValue
    }

  private fun tierPolicy(read: Boolean, write: Boolean): CachePolicy =
    when {
      read && write -> CachePolicy.ENABLED
      read -> CachePolicy.READ_ONLY
      write -> CachePolicy.WRITE_ONLY
      else -> CachePolicy.DISABLED
    }

  companion object {
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Must equal `NukeImageLoader.diskCacheBytes` on iOS. */
    const val DISK_CACHE_BYTES = 150L * 1024 * 1024

    @OptIn(ExperimentalCoilApi::class)
    private fun buildImageLoader(context: Context): ImageLoader {
      // Explicit client rather than RN's shared OkHttpClientProvider so that
      // TurboImage's network behaviour does not change with the host app's
      // interceptors. TODO: expose an opt-in hook for auth headers/cookies.
      val okHttpClient =
        OkHttpClient.Builder()
          // Application interceptor: sees the token header before the
          // network layer, strips it, and counts response bytes.
          .addInterceptor(ProgressInterceptor())
          .connectTimeout(15, TimeUnit.SECONDS)
          .readTimeout(30, TimeUnit.SECONDS)
          .build()

      return ImageLoader.Builder(context)
        .components {
          add(
            OkHttpNetworkFetcherFactory(
              callFactory = { okHttpClient },
              cacheStrategy = { CacheStrategy.DEFAULT },
              concurrentRequestStrategy = { DeDupeConcurrentRequestStrategy() },
            )
          )
        }
        .memoryCache { MemoryCache.Builder().maxSizePercent(context, 0.25).build() }
        .diskCache {
          DiskCache.Builder()
            .directory(context.cacheDir.resolve("turboimage").toOkioPath())
            .maxSizeBytes(DISK_CACHE_BYTES)
            .build()
        }
        .build()
    }
  }
}
