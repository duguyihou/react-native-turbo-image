package com.turboimage.loader

import android.content.Context
import android.content.res.Resources
import android.graphics.ImageDecoder
import android.os.Build
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import android.widget.ImageView
import coil3.ImageLoader
import coil3.asDrawable
import coil3.network.HttpException
import coil3.network.httpHeaders
import coil3.request.Disposable
import coil3.request.allowHardware
import coil3.request.crossfade
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.ResolvedRequest
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Coil 3 adapter: loads, prefetches and cache operations for the seam.
 * Everything Coil-specific lives in this file and the two beside it:
 * CoilRequests.kt (how a resolved request becomes a Coil request) and
 * CoilLoaderSetup.kt (how the `ImageLoader` is built).
 *
 * Cross-platform cache contract (RFC rule 3, mirrored in NukeImageLoader.swift):
 *  * the disk tier is TurboImage's own Coil DiskCache of original bytes, the
 *    same size as Nuke's DataCache,
 *  * HTTP freshness is ignored there: OkHttp gets no `Cache`, and Coil's
 *    `CacheStrategy.DEFAULT` serves disk hits without consulting
 *    `Cache-Control`, which matches Nuke's `withDataCache` (`urlCache = nil`),
 *  * except for `cachePolicy="urlCache"` requests (`ResolvedRequest.httpCache`),
 *    whose disk tier is an HTTP cache: see [PolicyCacheStrategy],
 *  * concurrent requests for the same cache key are de-duplicated, which
 *    matches Nuke's default task coalescing.
 */
class CoilImageLoaderAdapter(context: Context) : ImageLoaderAdapter {
  private val appContext = context.applicationContext
  private val imageLoader: ImageLoader = buildImageLoader(appContext)

  override fun load(
    target: ImageView,
    request: ResolvedRequest,
    options: ImageLoaderAdapter.DisplayOptions,
    listener: ImageLoaderAdapter.Listener,
  ): LoadHandle {
    // `finished` enforces the seam contract on the main thread: no progress
    // after success/failure/cancel. Progress arrives on OkHttp threads and is
    // posted to main, where this flag is checked.
    var finished = false
    val token =
      ProgressInterceptor.register { completed, total ->
        // Asynchronous, because Coil's own callbacks are: Dispatchers.Main
        // posts asynchronous messages, which pass the sync barrier the view
        // system holds from scheduling a traversal until it runs (up to a
        // frame). A plain `post` waits behind that barrier, so when a small
        // image downloaded and decoded within one frame, onSuccess overtook
        // every progress message, `finished` dropped them all, and the load
        // reported no progress. Same kind of message, same queue: FIFO.
        val message = Message.obtain(mainHandler) { if (!finished) listener.onProgress(completed, total) }
        message.isAsynchronous = true
        mainHandler.sendMessage(message)
      }
    fun finish() {
      finished = true
      ProgressInterceptor.unregister(token)
    }

    // Coil keeps a view's last request, finished or not, and enqueues it
    // again every time the view is reattached to a window (FlatList's
    // removeClippedSubviews, react-native-screens). That restart is wanted
    // while a load is in flight, since Coil cancels it on detach. For a load
    // that has completed it is wrong:
    //   * a failed load would retry behind the view's back, and could paint
    //     an image JS was told had failed;
    //   * a view whose source was since cleared would get the old image
    //     back (the target paints regardless of the view's own guards);
    //   * a `noCache` source would download again on every reattach.
    // So a completed load is disposed, which is how Coil is told to forget a
    // request. It leaves the drawable alone.
    var completed = false
    var disposable: Disposable? = null
    fun complete() {
      finish()
      completed = true
      // Null when a memory-cache hit completes inside `enqueue` below, before
      // the disposable exists; that case is disposed right after `enqueue`.
      disposable?.dispose()
    }

    val coilRequest =
      request.toCoilRequest(target.context, target)
        .httpHeaders(
          request.networkHeaders().set(ProgressInterceptor.TOKEN_HEADER, token.toString()).build()
        )
        .target(KeepCurrentImageTarget(target))
        // Coil's crossfade already skips memory-cache hits (the seam rule)
        // and fades from the target's current drawable, i.e. the placeholder.
        .crossfade(options.fadeMillis)
        // Coil's default is true. When false, a hardware bitmap already in
        // the memory cache is not reused (Coil treats it as a miss).
        .allowHardware(options.allowHardware)
        .listener(
          onSuccess = { _, result ->
            complete()
            listener.onSuccess(result.image.width, result.image.height)
          },
          onError = { _, result ->
            complete()
            listener.onError(classify(result.throwable, request), result.throwable.message ?: "Unknown error")
          },
          // Not `complete()`: this is Coil cancelling on detach (or before the
          // first attach), and the request must survive to restart on attach.
          onCancel = { finish() },
        )
        .build()

    val enqueued = imageLoader.enqueue(coilRequest)
    disposable = enqueued
    if (completed) enqueued.dispose()
    // `dispose()` cancels the job and clears the ViewTarget, so no listener
    // fires afterwards (RFC §4.8, "Coil and the view's attach state"). A
    // no-op once Coil has moved on to another request for this view, so safe
    // after completion too.
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
        // A callback target, not the view: the view shows the result only if
        // its lifecycle still wants this placeholder.
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

  override fun prefetch(request: ResolvedRequest, onDone: (Boolean) -> Unit): LoadHandle {
    var finished = false
    val coilRequest =
      request.toCoilRequest(appContext, view = null)
        .httpHeaders(request.networkHeaders().build())
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

  override fun remove(requests: List<ResolvedRequest>, onDone: (Throwable?) -> Unit) {
    onDiskThread(
      work = {
        for (request in requests) {
          // Both disk namespaces, whichever policy stored the image.
          imageLoader.diskCache?.remove(request.cacheKey)
          imageLoader.diskCache?.remove(httpDiskKey(request.url))
        }
      },
      // Memory after disk, not before: a view that reloads in between would
      // otherwise read the disk copy back into memory, and the entry would
      // outlive the call that removed it.
      // Also when the disk work failed: whatever can still be evicted is.
      thenOnMain = { failure ->
        for (request in requests) {
          memoryKeysFor(request.cacheKey).forEach { imageLoader.memoryCache?.remove(it) }
        }
        onDone(failure)
      },
    )
  }

  /**
   * Runs blocking disk-cache [work] off the main thread, then [thenOnMain].
   * Coil's `DiskCache` is thread-safe but synchronous: `remove` and `clear`
   * write the journal and delete files, and the first access opens the cache.
   *
   * [thenOnMain] always runs, so the caller's promise always settles: with
   * null when [work] finished, with what it threw otherwise.
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
   *
   * Android's `ImageDecoder.DecodeException` is an `IOException`, and Coil
   * decodes stills with `ImageDecoder` where it can (`StaticImageDecoder`),
   * so it is checked before the transport rule. Without that, bytes that are
   * not an image (an HTML error page sent with a 200) reported `network`
   * here and `decode` on iOS. The adapter test
   * `aBodyNoDecoderRecognisesIsADecodeError` caught it; no smoke scenario
   * expects `decode`.
   */
  private fun classify(error: Throwable, request: ResolvedRequest): Int =
    when {
      error is HttpException && error.response.code == 504 && !request.allowNetwork ->
        LoadErrorCode.NOT_CACHED.nativeValue
      error is HttpException -> LoadErrorCode.NETWORK.nativeValue
      Build.VERSION.SDK_INT >= 28 && error is ImageDecoder.DecodeException -> LoadErrorCode.DECODE.nativeValue
      error is IOException -> LoadErrorCode.NETWORK.nativeValue
      else -> LoadErrorCode.DECODE.nativeValue
    }

  companion object {
    private const val LOG_TAG = "TurboImage"

    private val mainHandler = Handler(Looper.getMainLooper())

    // One thread, so removals and clears run in the order JS asked for them.
    private val diskExecutor: ExecutorService =
      Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "TurboImageDiskCache").apply { isDaemon = true }
      }

    /** The extra `transformations()` adds to memory keys (Coil 3 imageRequests.kt). */
    private const val TRANSFORMATIONS_EXTRA = "coil#transformations"
  }
}
