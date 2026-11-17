package com.turboimage.loader

import android.content.Context
import android.content.res.Resources
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.widget.ImageView
import coil3.Image
import coil3.ImageLoader
import coil3.asDrawable
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
import coil3.request.crossfade
import coil3.request.transformations
import coil3.size.Size
import coil3.transform.Transformation
import coil3.target.ImageViewTarget
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import java.io.IOException
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath
import android.graphics.Bitmap

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

/**
 * The core's processing step as one Coil transformation. Its `cacheKey` is
 * the core's processor key, which Coil adds to the memory key's extras, so
 * each variant is its own memory entry while the disk cache (keyed by
 * `diskCacheKey` alone) keeps one original, the same split Nuke makes.
 * Throwing fails the load; `classify` reports it as `decode`, like Nuke's
 * `processingFailed`.
 */
private class CoreProcessingTransformation(private val processorKey: String) : Transformation() {
  override val cacheKey: String = processorKey

  override suspend fun transform(input: Bitmap, size: Size): Bitmap =
    TurboImageCore.process(input, processorKey)
      ?: throw IllegalStateException("TurboImage processing failed ($processorKey)")
}

class CoilImageLoaderAdapter(context: Context) : ImageLoaderAdapter {
  private val appContext = context.applicationContext
  private val imageLoader: ImageLoader = buildImageLoader(appContext)

  override fun load(
    target: ImageView,
    request: ResolvedRequest,
    fadeMillis: Int,
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
        // Coil's crossfade already skips memory-cache hits (the seam rule)
        // and fades from the target's current drawable, i.e. the placeholder.
        .crossfade(fadeMillis)
        .applyProcessing(request)
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

  override fun prefetch(request: ResolvedRequest, onDone: (Boolean) -> Unit): LoadHandle {
    var finished = false
    val coilRequest =
      ImageRequest.Builder(appContext)
        .data(request.url)
        .memoryCacheKey(request.cacheKey)
        .diskCacheKey(request.cacheKey)
        .memoryCachePolicy(tierPolicy(request.memoryRead, request.memoryWrite))
        .diskCachePolicy(tierPolicy(request.diskRead, request.diskWrite))
        .networkCachePolicy(if (request.allowNetwork) CachePolicy.ENABLED else CachePolicy.DISABLED)
        .listener(
          onSuccess = { _, _ -> if (!finished) { finished = true; onDone(true) } },
          onError = { _, _ -> if (!finished) { finished = true; onDone(false) } },
        )
        .build()
    val disposable = imageLoader.enqueue(coilRequest)
    return LoadHandle {
      finished = true
      disposable.dispose()
    }
  }

  // Coil keys memory entries by key *and* extras (e.g. the resolved size of
  // the view that loaded it, or the processing step), so an exact
  // Key(cacheKey) lookup would miss. TurboImage owns the key string; match on
  // it across the (small) key set. `remove` thereby evicts every processed
  // variant too.
  private fun memoryKeysFor(cacheKey: String) =
    imageLoader.memoryCache?.keys?.filter { it.key == cacheKey }.orEmpty()

  override fun remove(cacheKey: String) {
    memoryKeysFor(cacheKey).forEach { imageLoader.memoryCache?.remove(it) }
    imageLoader.diskCache?.remove(cacheKey)
  }

  override fun clearMemoryCache() {
    imageLoader.memoryCache?.clear()
  }

  override fun clearDiskCache() {
    imageLoader.diskCache?.clear()
  }

  override fun memoryCachedDrawable(cacheKey: String, resources: Resources): Drawable? {
    // The unprocessed image only, like Nuke's (imageID, no processors) key:
    // a blurred variant must not stand in as another view's placeholder.
    val key = memoryKeysFor(cacheKey).firstOrNull { TRANSFORMATIONS_EXTRA !in it.extras } ?: return null
    return imageLoader.memoryCache?.get(key)?.image?.asDrawable(resources)
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

  /**
   * Processed loads decode at the original size. Otherwise Coil would decode
   * to the view's size first, and `blur` (in image pixels) and `resize` would
   * act on a different bitmap than on iOS, where Nuke decodes the original.
   * TODO: decode-time downsampling to the `resize` width on both platforms
   * (Nuke thumbnail options, Coil size), to cut peak memory for large photos.
   */
  private fun ImageRequest.Builder.applyProcessing(request: ResolvedRequest) = apply {
    if (request.processorKey.isNotEmpty()) {
      size(Size.ORIGINAL)
      transformations(CoreProcessingTransformation(request.processorKey))
    }
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

    /** The extra `transformations()` adds to memory keys (Coil 3 imageRequests.kt). */
    private const val TRANSFORMATIONS_EXTRA = "coil#transformations"

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
