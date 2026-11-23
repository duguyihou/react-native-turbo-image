package com.turboimage.loader

import android.content.Context
import android.os.Build
import coil3.Extras
import coil3.ImageLoader
import coil3.annotation.ExperimentalCoilApi
import coil3.disk.DiskCache
import coil3.getExtra
import coil3.gif.AnimatedImageDecoder
import coil3.gif.GifDecoder
import coil3.memory.MemoryCache
import coil3.network.CacheStrategy
import coil3.network.DeDupeConcurrentRequestStrategy
import coil3.network.NetworkRequest
import coil3.network.NetworkResponse
import coil3.network.cachecontrol.CacheControlCacheStrategy
import coil3.network.okhttp.OkHttpNetworkFetcherFactory
import coil3.request.Options
import coil3.svg.SvgDecoder
import com.turboimage.core.TurboImageCore
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okio.Path.Companion.toOkioPath

// The one Coil `ImageLoader` TurboImage uses, built once per process: its
// HTTP client, decoders, caches and disk-cache rules. Part of the Coil
// adapter; see CoilImageLoaderAdapter.kt for the cache contract these
// choices implement.

/** Must equal `NukeImageLoader.diskCacheBytes` on iOS. */
internal const val DISK_CACHE_BYTES = 150L * 1024 * 1024

@OptIn(ExperimentalCoilApi::class)
internal fun buildImageLoader(context: Context): ImageLoader {
  // Explicit client rather than RN's shared OkHttpClientProvider so that
  // TurboImage's network behaviour does not change with the host app's
  // interceptors.
  //
  // No cookie jar, as in 1.x (RFC §4.2). React Native's cookie store
  // (`ForwardingCookieHandler`) starts the platform CookieManager, and with
  // it WebView, on first use: that held up a process's first network image
  // by 0.2–0.6 s in every app. A session goes in `source.headers` instead.
  // TODO: an opt-in for React Native's cookies, and a hook for default
  // headers or an interceptor.
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
      // `scaleToDensity`: an SVG's own size is in dp, not raw pixels, the
      // way iOS reads it in points. It only matters when the request asks
      // for the original size (`resizeMode="center"`, `blur` without
      // `resize`); otherwise the SVG is drawn at the view's size whatever
      // its own size is. Without it a 120×80 SVG came out 120×80 px, a
      // third of its size on a 2.6× screen. The wrapper covers
      // `allowDownscaling={false}`, which must not shrink an SVG to its
      // own size either.
      add(VectorSizeDecoderFactory(SvgDecoder.Factory(scaleToDensity = true)))
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
internal class PolicyCacheStrategy : CacheStrategy {
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
