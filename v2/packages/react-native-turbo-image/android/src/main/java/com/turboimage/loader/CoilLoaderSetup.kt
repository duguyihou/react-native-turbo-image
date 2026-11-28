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

// Builds TurboImage's single Coil `ImageLoader`: client, decoders, caches.

/** Must equal `NukeImageLoader.diskCacheBytes` on iOS. */
internal const val DISK_CACHE_BYTES = 150L * 1024 * 1024

@OptIn(ExperimentalCoilApi::class)
internal fun buildImageLoader(context: Context, cacheSizes: CacheSizes = CacheSizes()): ImageLoader {
  // Own client, not RN's, so app interceptors don't affect us. No cookie
  // jar: RN's starts WebView and delays the first image.
  // TODO: opt-in RN cookies, and a hook for default headers or interceptors.
  // Built lazily on Coil's fetch thread to keep it off the first frame.
  val buildOkHttpClient = {
    OkHttpClient.Builder()
      // Strips the progress token header and counts bytes.
      .addInterceptor(ProgressInterceptor())
      .addInterceptor(userAgentInterceptor(context))
      .connectTimeout(15, TimeUnit.SECONDS)
      .readTimeout(30, TimeUnit.SECONDS)
      .build()
  }

  return ImageLoader.Builder(context)
    .components {
      // Tried before Coil's built-in bitmap decoder.
      add(ApngDecoder.Factory())
      if (Build.VERSION.SDK_INT >= 28) {
        add(AnimatedImageDecoder.Factory())
      } else {
        add(GifDecoder.Factory())
      }
      // `scaleToDensity`: an SVG's own size is in dp, as iOS uses points.
      // The wrapper handles `allowDownscaling={false}`.
      add(VectorSizeDecoderFactory(SvgDecoder.Factory(scaleToDensity = true)))
      add(
        OkHttpNetworkFetcherFactory(
          callFactory = buildOkHttpClient,
          cacheStrategy = { PolicyCacheStrategy() },
          concurrentRequestStrategy = { DeDupeConcurrentRequestStrategy() },
        )
      )
    }
    .memoryCache {
      MemoryCache.Builder()
        .apply {
          if (cacheSizes.maxMemoryCost > 0) maxSizeBytes(cacheSizes.maxMemoryCost)
          else maxSizePercent(context, 0.25)
        }
        .build()
    }
    .diskCache {
      DiskCache.Builder()
        .directory(context.cacheDir.resolve("turboimage").toOkioPath())
        // Also holds `urlCache` HTTP responses (`httpDiskKey`).
        .maxSizeBytes(if (cacheSizes.maxDiskSize > 0) cacheSizes.maxDiskSize else DISK_CACHE_BYTES)
        .build()
    }
    .build()
}

/**
 * Some hosts (e.g. Wikimedia) reject OkHttp's default User-Agent, so send
 * `<App>/<version> TurboImage/<core> (Android <release>)`, like iOS's shape.
 * A `User-Agent` in `source.headers` wins.
 */
private fun userAgentInterceptor(context: Context): okhttp3.Interceptor {
  val packageInfo = runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
  val label = context.applicationInfo.loadLabel(context.packageManager).toString()
  // OkHttp rejects non-ASCII header values; app labels may contain any.
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
 * Per-request disk-cache rules (Coil allows one strategy per fetcher):
 * keyed requests use `CacheStrategy.DEFAULT` (always valid); `urlCache`
 * requests use `CacheControlCacheStrategy`, like `URLCache` on iOS.
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
