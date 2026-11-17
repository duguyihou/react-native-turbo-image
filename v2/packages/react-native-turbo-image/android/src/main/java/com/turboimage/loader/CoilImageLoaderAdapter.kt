package com.turboimage.loader

import android.content.Context
import android.content.res.Resources
import android.graphics.drawable.Drawable
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.View
import android.widget.ImageView
import coil3.Extras
import coil3.Image
import coil3.ImageLoader
import coil3.asDrawable
import coil3.annotation.ExperimentalCoilApi
import coil3.getExtra
import coil3.disk.DiskCache
import coil3.gif.AnimatedImageDecoder
import coil3.gif.GifDecoder
import coil3.svg.SvgDecoder
import android.os.Build
import coil3.memory.MemoryCache
import coil3.network.CacheStrategy
import coil3.network.DeDupeConcurrentRequestStrategy
import coil3.network.HttpException
import coil3.network.NetworkHeaders
import coil3.network.NetworkRequest
import coil3.network.NetworkResponse
import coil3.network.cachecontrol.CacheControlCacheStrategy
import coil3.network.httpHeaders
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import coil3.request.Options
import coil3.request.allowHardware
import coil3.request.crossfade
import coil3.request.transformations
import coil3.size.Dimension
import coil3.size.Precision
import coil3.size.Scale
import coil3.size.Size
import coil3.size.SizeResolver
import coil3.transform.Transformation
import coil3.target.ImageViewTarget
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath
import android.graphics.Bitmap

/**
 * Coil 3 adapter. Everything Coil-specific lives in this file.
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

/**
 * The size React Native laid the view out at, in pixels, as a Coil size.
 *
 * Not Coil's own `ViewSizeResolver`: that reads `LayoutParams` first, and
 * treats `WRAP_CONTENT` as "no bound". Fabric positions views itself and
 * leaves them with their parent's default params, which are `WRAP_CONTENT`,
 * so Coil saw every TurboImage as unbounded and decoded the original (the
 * smoke scenario `downscaled` reported 3000×2000 for a ~1000 px card).
 *
 * Fabric applies props, and so starts loads, before it lays the view out, so
 * this waits for the first layout pass. A view laid out with no area gets
 * the original, as on iOS: it shows nothing, but its load must still finish
 * (and such views are used to warm the cache).
 */
private class LaidOutSizeResolver(private val view: View) : SizeResolver {
  override suspend fun size(): Size {
    if (view.isLaidOut) return currentSize()
    return suspendCancellableCoroutine { continuation ->
      val listener =
        object : View.OnLayoutChangeListener {
          override fun onLayoutChange(
            v: View, left: Int, top: Int, right: Int, bottom: Int,
            oldLeft: Int, oldTop: Int, oldRight: Int, oldBottom: Int,
          ) {
            view.removeOnLayoutChangeListener(this)
            continuation.resume(currentSize())
          }
        }
      view.addOnLayoutChangeListener(listener)
      continuation.invokeOnCancellation { view.removeOnLayoutChangeListener(listener) }
    }
  }

  private fun currentSize(): Size =
    if (view.width > 0 && view.height > 0) Size(view.width, view.height) else Size.ORIGINAL
}

/**
 * Picks the disk-cache rules per request. Coil takes one strategy per
 * fetcher factory, but the choice is a property of the request (the core's
 * `httpCache`), so this one delegates on a request extra:
 *
 *  * keyed requests: `CacheStrategy.DEFAULT`, where a disk entry is always
 *    valid and nothing is revalidated;
 *  * HTTP-cache requests: Coil's `CacheControlCacheStrategy`, which serves an
 *    entry only while `Cache-Control`/`Expires` say it is fresh, revalidates
 *    a stale one with `If-None-Match`/`If-Modified-Since`, and refuses to
 *    store `no-store`. That is what `URLCache` does for Nuke on iOS.
 *
 * The two kinds never see each other's entries: the adapter gives HTTP-cache
 * requests their own disk key (see `diskKey`).
 */
@OptIn(ExperimentalCoilApi::class)
private class PolicyCacheStrategy : CacheStrategy {
  private val keyed = CacheStrategy.DEFAULT
  private val http = CacheControlCacheStrategy()

  private fun strategyFor(options: Options) = if (options.getExtra(HTTP_CACHE)) http else keyed

  override suspend fun read(
    cacheResponse: NetworkResponse,
    networkRequest: NetworkRequest,
    options: Options,
  ) = strategyFor(options).read(cacheResponse, networkRequest, options)

  override suspend fun write(
    cacheResponse: NetworkResponse?,
    networkRequest: NetworkRequest,
    networkResponse: NetworkResponse,
    options: Options,
  ) = strategyFor(options).write(cacheResponse, networkRequest, networkResponse, options)

  companion object {
    /** Set on requests whose disk tier is the HTTP cache. */
    val HTTP_CACHE = Extras.Key(default = false)
  }
}

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

  override fun remove(request: ResolvedRequest) {
    memoryKeysFor(request.cacheKey).forEach { imageLoader.memoryCache?.remove(it) }
    // Both disk namespaces, whichever policy stored the image.
    imageLoader.diskCache?.remove(request.cacheKey)
    imageLoader.diskCache?.remove(httpDiskKey(request.url))
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
   * Everything a view load and a prefetch share. Mechanical translation
   * only; the C++ core already decided policy, keys and decode size.
   * [view] is the view the image is for; null for a prefetch.
   */
  private fun ResolvedRequest.toCoilRequest(context: Context, view: View?): ImageRequest.Builder =
    ImageRequest.Builder(context)
      .data(url)
      .memoryCacheKey(cacheKey)
      .diskCacheKey(diskKey())
      .memoryCachePolicy(tierPolicy(memoryRead, memoryWrite))
      .diskCachePolicy(tierPolicy(diskRead, diskWrite))
      .networkCachePolicy(if (allowNetwork) CachePolicy.ENABLED else CachePolicy.DISABLED)
      .apply {
        // Read back by PolicyCacheStrategy, which then applies HTTP freshness.
        if (httpCache) extras[PolicyCacheStrategy.HTTP_CACHE] = true
        applyDecodeSize(decode, view)
        if (processorKey.isNotEmpty()) {
          transformations(CoreProcessingTransformation(processorKey))
        }
      }

  /**
   * The core's decode target as Coil sizing. Coil samples while decoding
   * (`inSampleSize`, then a density scale), so the full bitmap is never
   * allocated, like ImageIO thumbnails in the Nuke adapter.
   */
  private fun ImageRequest.Builder.applyDecodeSize(decode: ResolvedRequest.DecodeSize, view: View?) {
    when (decode) {
      ResolvedRequest.DecodeSize.Original -> size(Size.ORIGINAL)
      is ResolvedRequest.DecodeSize.View -> {
        // Without a view (prefetch) there is no size to bound the decode
        // with; the core never asks for a view-sized prefetch anyway.
        if (view != null) size(LaidOutSizeResolver(view)) else size(Size.ORIGINAL)
        scale(if (decode.fill) Scale.FILL else Scale.FIT)
      }
      is ResolvedRequest.DecodeSize.Width -> {
        size(Dimension(decode.pixels), Dimension.Undefined)
        scale(Scale.FIT)
      }
    }
    // Every target is an upper bound (core rule): EXACT would scale a
    // smaller image *up* to it.
    precision(Precision.INEXACT)
  }

  /**
   * HTTP-cache entries live in the same Coil DiskCache under their own
   * prefix and are keyed by URL, the way iOS's URLCache is a separate store
   * keyed by URL. The prefix cannot collide with a keyed entry: `cacheKey`
   * defaults to an http(s) URL, and an app would have to choose this exact
   * string as its explicit key.
   */
  private fun ResolvedRequest.diskKey() = if (httpCache) httpDiskKey(url) else cacheKey

  private fun httpDiskKey(url: String) = "turboimage-http:$url"

  /** The request's headers, in order; `add` keeps repeated names. */
  private fun ResolvedRequest.networkHeaders(): NetworkHeaders.Builder =
    NetworkHeaders.Builder().apply { headers.forEach { (name, value) -> add(name, value) } }

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

    /**
     * OkHttp's default `okhttp/x.y` User-Agent is refused by some major image
     * hosts (Wikimedia answers 403), where iOS's CFNetwork default
     * (`<App>/<build> CFNetwork/… Darwin/…`) is accepted. This mirrors that
     * shape: `<App>/<version> TurboImage/<core> (Android <release>)`. A
     * `User-Agent` in `source.headers` wins. 1.x sent OkHttp's default.
     */
    private fun userAgentInterceptor(context: Context): okhttp3.Interceptor {
      val packageInfo = runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
      val label = context.applicationInfo.loadLabel(context.packageManager).toString()
      // Product tokens must be ASCII HTTP tokens (OkHttp rejects non-ASCII
      // header values outright); app labels may hold spaces or any script.
      val app =
        label.filter { it.code < 128 && (it.isLetterOrDigit() || it in "!#$%&'*+-.^_`|~") }
          .ifEmpty { context.packageName }
      val userAgent =
        "$app/${packageInfo?.versionName ?: "0"} TurboImage/${TurboImageCore.coreVersion} " +
          "(Android ${Build.VERSION.RELEASE})"
      return okhttp3.Interceptor { chain ->
        val request = chain.request()
        chain.proceed(
          if (request.header("User-Agent") != null) request
          else request.newBuilder().header("User-Agent", userAgent).build()
        )
      }
    }

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
          .addInterceptor(userAgentInterceptor(context))
          .connectTimeout(15, TimeUnit.SECONDS)
          .readTimeout(30, TimeUnit.SECONDS)
          .build()

      return ImageLoader.Builder(context)
        .components {
          // Format decoders, chosen by content (the iOS adapter does the
          // same with ImageIO and CoreSVG). Added components are tried before
          // Coil's built-in bitmap decoder, so these see the bytes first;
          // a factory that does not recognise them returns null.
          add(ApngDecoder.Factory())
          if (Build.VERSION.SDK_INT >= 28) {
            add(AnimatedImageDecoder.Factory())
          } else {
            add(GifDecoder.Factory())
          }
          add(SvgDecoder.Factory())
          add(
            OkHttpNetworkFetcherFactory(
              callFactory = { okHttpClient },
              cacheStrategy = { PolicyCacheStrategy() },
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
