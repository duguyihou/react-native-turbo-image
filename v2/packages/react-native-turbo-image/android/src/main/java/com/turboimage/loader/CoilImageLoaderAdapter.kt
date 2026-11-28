package com.turboimage.loader

import android.content.Context
import android.content.res.Resources
import android.graphics.drawable.Animatable
import android.graphics.ImageDecoder
import android.os.Build
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import android.widget.ImageView
import coil3.BitmapImage
import coil3.Image
import coil3.ImageLoader
import coil3.asDrawable
import coil3.memory.MemoryCache
import coil3.network.HttpException
import coil3.network.httpHeaders
import coil3.request.CachePolicy
import coil3.request.Disposable
import coil3.request.allowHardware
import coil3.request.crossfade
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.ResolvedRequest
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Coil 3 adapter for the seam. Cache contract (RFC rule 3, as on iOS): the
 * disk tier holds original bytes and ignores HTTP freshness, except under
 * `urlCache` ([PolicyCacheStrategy]); concurrent same-key requests dedupe.
 */
internal class CoilImageLoaderAdapter(context: Context, cacheSizes: CacheSizes = CacheSizes()) : ImageLoaderAdapter {
  private val appContext = context.applicationContext
  // Internal for instrumented tests.
  internal val imageLoader: ImageLoader = buildImageLoader(appContext, cacheSizes)

  override fun load(
    target: ImageView,
    request: ResolvedRequest,
    options: ImageLoaderAdapter.DisplayOptions,
    listener: ImageLoaderAdapter.Listener,
  ): LoadHandle {
    // No progress after success/failure/cancel; checked on the main thread.
    var finished = false
    // Null when nothing listens: no token header, no byte counting.
    val token =
      if (!options.reportProgress) null
      else ProgressInterceptor.register { completed, total ->
        // Asynchronous like Coil's own callbacks, so progress stays ordered
        // before onSuccess; a plain `post` waits behind the sync barrier.
        val message = Message.obtain(mainHandler) { if (!finished) listener.onProgress(completed, total) }
        message.isAsynchronous = true
        mainHandler.sendMessage(message)
      }
    fun finish() {
      finished = true
      token?.let(ProgressInterceptor::unregister)
    }

    // Coil re-enqueues a view's last request on every reattach. Fine while in
    // flight, wrong once done (silent retries, stale images, re-downloads),
    // so dispose a completed load. The drawable stays.
    var completed = false
    var disposable: Disposable? = null
    fun complete() {
      finish()
      completed = true
      // Null on a memory hit inside `enqueue`; disposed right after it.
      disposable?.dispose()
    }

    val coilRequest =
      request.toCoilRequest(target.context, target)
        .httpHeaders(
          request.networkHeaders()
            .apply { if (token != null) set(ProgressInterceptor.TOKEN_HEADER, token.toString()) }
            .build()
        )
        .target(KeepCurrentImageTarget(target))
        // Skips memory hits and fades from the current drawable.
        .crossfade(options.fadeMillis)
        // When false, a cached hardware bitmap counts as a miss.
        .allowHardware(options.allowHardware)
        .listener(
          onSuccess = { _, result ->
            complete()
            listener.onSuccess(result.image.width, result.image.height, isAnimated(result.image, target))
          },
          onError = { _, result ->
            complete()
            listener.onError(classify(result.throwable, request), result.throwable.message ?: "Unknown error")
          },
          // Not `complete()`: a detach cancel must restart on attach.
          onCancel = { finish() },
        )
        .build()

    val enqueued = imageLoader.enqueue(coilRequest)
    disposable = enqueued
    if (completed) enqueued.dispose()
    // `dispose()` stops all listeners; safe after completion.
    return LoadHandle {
      finish()
      enqueued.dispose()
    }
  }

  override fun loadPlaceholder(
    sizeOf: ImageView,
    request: ResolvedRequest,
    onDone: (Drawable?) -> Unit,
  ): LoadHandle {
    var finished = false
    val coilRequest =
      request.toCoilRequest(sizeOf.context, sizeOf)
        .httpHeaders(request.networkHeaders().build())
        // Not the view: its lifecycle decides whether to show it.
        .target(
          onSuccess = { image ->
            if (!finished) {
              finished = true
              onDone(image.asDrawable(sizeOf.resources))
            }
          },
          onError = {
            if (!finished) {
              finished = true
              onDone(null)
            }
          },
        )
        .build()
    val disposable = imageLoader.enqueue(coilRequest)
    return LoadHandle {
      finished = true
      disposable.dispose()
    }
  }

  override fun imageSize(
    request: ResolvedRequest,
    onSize: (width: Int, height: Int) -> Unit,
    onError: (code: Int, message: String) -> Unit,
  ): LoadHandle {
    var finished = false
    val coilRequest =
      request.toCoilRequest(appContext, view = null)
        .httpHeaders(request.networkHeaders().build())
        .decoderFactory(HeaderSizeDecoder.Factory())
        // Never store the size-only result; a cached full image is fine.
        .memoryCachePolicy(if (request.memoryRead) CachePolicy.READ_ONLY else CachePolicy.DISABLED)
        .listener(
          onSuccess = { _, result ->
            if (!finished) {
              finished = true
              onSize(result.image.width, result.image.height)
            }
          },
          onError = { _, result ->
            if (!finished) {
              finished = true
              onError(classify(result.throwable, request), result.throwable.message ?: "Unknown error")
            }
          },
        )
        .build()
    val disposable = imageLoader.enqueue(coilRequest)
    return LoadHandle {
      finished = true
      disposable.dispose()
    }
  }

  override fun prefetch(request: ResolvedRequest, onDone: (Boolean) -> Unit): LoadHandle {
    var finished = false
    val coilRequest =
      request.toCoilRequest(appContext, view = null)
        .httpHeaders(request.networkHeaders().build())
        .apply {
          // Disk-only prefetch: read just the header, allocate no pixels.
          if (!request.memoryWrite) decoderFactory(HeaderSizeDecoder.Factory())
        }
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

  // Coil keys entries by key and extras, so match on the key string alone
  // to find every variant.
  private fun memoryKeysFor(cacheKey: String) =
    imageLoader.memoryCache?.keys?.filter { it.key == cacheKey }.orEmpty()

  override fun remove(requests: List<ResolvedRequest>, onDone: (Throwable?) -> Unit) {
    onDiskThread(
      work = {
        for (request in requests) {
          // Both disk namespaces.
          imageLoader.diskCache?.remove(request.cacheKey)
          imageLoader.diskCache?.remove(httpDiskKey(request.url))
        }
      },
      // Memory after disk, or a reload in between could repopulate it.
      // Runs even if the disk work failed.
      thenOnMain = { failure ->
        for (request in requests) {
          memoryKeysFor(request.cacheKey).forEach { imageLoader.memoryCache?.remove(it) }
        }
        onDone(failure)
      },
    )
  }

  /**
   * Runs blocking disk-cache [work] off the main thread, then always runs
   * [thenOnMain] with null or what [work] threw.
   */
  private fun onDiskThread(work: () -> Unit, thenOnMain: (Throwable?) -> Unit) {
    diskExecutor.execute {
      val failure =
        try {
          work()
          null
        } catch (e: Exception) {
          Log.w(LOG_TAG, "Disk cache operation failed", e)
          e
        }
      mainHandler.post { thenOnMain(failure) }
    }
  }

  override fun clearMemoryCache() {
    imageLoader.memoryCache?.clear()
  }

  override fun clearDiskCache(onDone: (Throwable?) -> Unit) {
    onDiskThread(work = { imageLoader.diskCache?.clear() }, thenOnMain = onDone)
  }

  override fun memoryCachedDrawable(cacheKey: String, resources: Resources): Drawable? {
    // Unprocessed only: a blurred variant must not be another view's placeholder.
    val memoryCache = imageLoader.memoryCache ?: return null
    // Fast path for view-sized entries; the key scan is the fallback for
    // original-size ones.
    memoryCache[MemoryCache.Key(cacheKey)]?.let { return it.image.asDrawable(resources) }
    val key = memoryKeysFor(cacheKey).firstOrNull { TRANSFORMATIONS_EXTRA !in it.extras } ?: return null
    return memoryCache[key]?.image?.asDrawable(resources)
  }

  /**
   * Maps Coil failures to `turboimage::LoadErrorCode`, in step with iOS.
   * A 504 means "not cached" only when the policy forbade the network, and
   * is otherwise `network`: a gateway timeout, or Coil's synthetic answer
   * while offline, either of which may pass. Any other error status is the
   * server's answer and would come again (`http`).
   * `ImageDecoder.DecodeException` is an `IOException`, so check it first.
   * Anything else non-transport is a decode failure.
   */
  private fun classify(error: Throwable, request: ResolvedRequest): Int =
    when {
      error is HttpException && error.response.code == 504 && !request.allowNetwork ->
        LoadErrorCode.NOT_CACHED.nativeValue
      error is HttpException && error.response.code == 504 -> LoadErrorCode.NETWORK.nativeValue
      error is HttpException -> LoadErrorCode.HTTP.nativeValue
      Build.VERSION.SDK_INT >= 28 && error is ImageDecoder.DecodeException -> LoadErrorCode.DECODE.nativeValue
      error is IOException -> LoadErrorCode.NETWORK.nativeValue
      else -> LoadErrorCode.DECODE.nativeValue
    }

  // A still is a BitmapImage; animated formats decode to an Animatable drawable.
  private fun isAnimated(image: Image, view: ImageView): Boolean =
    image !is BitmapImage && image.asDrawable(view.resources) is Animatable

  companion object {
    private const val LOG_TAG = "TurboImage"

    private val mainHandler = Handler(Looper.getMainLooper())

    // One thread, so removals and clears keep JS's order.
    private val diskExecutor: ExecutorService =
      Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "TurboImageDiskCache").apply { isDaemon = true }
      }

    /** The extra `transformations()` adds to memory keys (Coil 3 imageRequests.kt). */
    private const val TRANSFORMATIONS_EXTRA = "coil#transformations"
  }
}
