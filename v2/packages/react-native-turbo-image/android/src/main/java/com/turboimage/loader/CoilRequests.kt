package com.turboimage.loader

import android.content.Context
import android.graphics.Bitmap
import android.view.View
import android.widget.ImageView
import coil3.Extras
import coil3.Image
import coil3.ImageLoader
import coil3.decode.Decoder
import coil3.fetch.SourceFetchResult
import coil3.getExtra
import coil3.network.NetworkHeaders
import coil3.request.CachePolicy
import coil3.request.ImageRequest
import coil3.request.Options
import coil3.request.transformations
import coil3.size.Dimension
import coil3.size.Precision
import coil3.size.Scale
import coil3.size.Size
import coil3.size.SizeResolver
import coil3.target.ImageViewTarget
import coil3.transform.Transformation
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

// How one resolved request becomes one Coil request: the translation itself
// first, then the four Coil extension points it plugs in (target,
// transformation, size resolver, vector decoder). Part of the Coil adapter; see
// CoilImageLoaderAdapter.kt for what is done with the request.

/**
 * Everything a view load and a prefetch share. Mechanical translation
 * only; the C++ core already decided policy, keys and decode size.
 * [view] is the view the image is for; null for a prefetch.
 */
internal fun ResolvedRequest.toCoilRequest(context: Context, view: View?): ImageRequest.Builder =
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
      // Only the decoder learns whether the bytes are an SVG, so the size a
      // vector should be drawn at travels with the request and
      // VectorSizeDecoderFactory picks it up. The two targets differ only
      // when `allowDownscaling` is off.
      if (vectorDecode != decode) {
        vectorTarget(vectorDecode, view)?.let { extras[VectorTarget.KEY] = it }
      }
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
 * The core's target for a vector as something a decoder can resolve, or
 * null when it comes to the SVG's own size, which is what the request
 * (`Size.ORIGINAL`) already asks the decoder for.
 */
private fun vectorTarget(decode: ResolvedRequest.DecodeSize, view: View?): VectorTarget? =
  when (decode) {
    ResolvedRequest.DecodeSize.Original -> null
    // A prefetch has no view. Its decode is not kept in memory for a view
    // to reuse at another size anyway (Coil re-draws a vector per size).
    is ResolvedRequest.DecodeSize.View ->
      view?.let { VectorTarget(LaidOutSizeResolver(it), if (decode.fill) Scale.FILL else Scale.FIT) }
    is ResolvedRequest.DecodeSize.Width ->
      VectorTarget(SizeResolver(Size(Dimension(decode.pixels), Dimension.Undefined)), Scale.FIT)
  }

/**
 * HTTP-cache entries live in the same Coil DiskCache under their own
 * prefix and are keyed by URL, the way iOS's URLCache is a separate store
 * keyed by URL. The prefix cannot collide with a keyed entry: `cacheKey`
 * defaults to an http(s) URL, and an app would have to choose this exact
 * string as its explicit key.
 */
private fun ResolvedRequest.diskKey() = if (httpCache) httpDiskKey(url) else cacheKey

internal fun httpDiskKey(url: String) = "turboimage-http:$url"

/** The request's headers, in order; `add` keeps repeated names. */
internal fun ResolvedRequest.networkHeaders(): NetworkHeaders.Builder =
  NetworkHeaders.Builder().apply { headers.forEach { (name, value) -> add(name, value) } }

private fun tierPolicy(read: Boolean, write: Boolean): CachePolicy =
  when {
    read && write -> CachePolicy.ENABLED
    read -> CachePolicy.READ_ONLY
    write -> CachePolicy.WRITE_ONLY
    else -> CachePolicy.DISABLED
  }

/**
 * A Coil ImageView target that only ever sets the *loaded* image. Coil's
 * default target sets the request's placeholder on start and its error
 * image on failure; both are null for us, so it would wipe the TurboImage
 * placeholder the view already shows. iOS keeps the placeholder on start and
 * on failure, so Android must too (RFC rule 3). Subclassing (rather than a
 * plain Target) keeps Coil's view-lifecycle handling: detach/attach
 * cancel/restart, see RFC open question 1.
 */
internal class KeepCurrentImageTarget(view: ImageView) : ImageViewTarget(view) {
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
 *
 * The wait ends after one turn of the main loop even if no layout pass came.
 * `View.isLaidOut` is cleared every time a view is attached to or detached
 * from a window, and React Native lays a view out only when its frame
 * changes. So a view that a `removeClippedSubviews` parent (every FlatList
 * on Android) took out and put back is "not laid out" for good, and a load
 * that started or restarted then would wait for a pass that never comes.
 * Fabric lays a new view out in the same mount transaction that attaches
 * it, which is before anything posted from here can run, so the first load
 * still sees its real size.
 */
private class LaidOutSizeResolver(private val view: View) : SizeResolver {
  override suspend fun size(): Size {
    if (view.isLaidOut) return currentSize()
    return suspendCancellableCoroutine { continuation ->
      lateinit var stopWaiting: () -> Unit
      val proceed = Runnable {
        stopWaiting()
        if (continuation.isActive) continuation.resume(currentSize())
      }
      val listener =
        object : View.OnLayoutChangeListener {
          override fun onLayoutChange(
            v: View, left: Int, top: Int, right: Int, bottom: Int,
            oldLeft: Int, oldTop: Int, oldRight: Int, oldBottom: Int,
          ) = proceed.run()
        }
      stopWaiting = {
        view.removeOnLayoutChangeListener(listener)
        view.removeCallbacks(proceed)
      }
      view.addOnLayoutChangeListener(listener)
      view.post(proceed)
      continuation.invokeOnCancellation { stopWaiting() }
    }
  }

  private fun currentSize(): Size =
    if (view.width > 0 && view.height > 0) Size(view.width, view.height) else Size.ORIGINAL
}

/** Where to draw a vector image, when that is not the request's own size. */
internal class VectorTarget(val size: SizeResolver, val scale: Scale) {
  companion object {
    /** Absent on most requests: the request's size is the vector's too. */
    val KEY = Extras.Key<VectorTarget?>(default = null)
  }
}

/**
 * Draws a vector at the request's [VectorTarget] instead of at the size
 * the request names.
 *
 * `allowDownscaling={false}` asks Coil for `Size.ORIGINAL`, which is right
 * for a bitmap (every pixel) and wrong for an SVG: its "original" is its
 * nominal size, usually smaller than the view, and the view then scales
 * that bitmap up (measured: 315×210 stretched over 630×420). The request
 * cannot ask for the view's size instead, because it is built before the
 * bytes are known and would downscale a bitmap. So the swap happens here,
 * the first place that knows the bytes are an SVG.
 *
 * [delegate] decides what counts as a vector: this only ever changes the
 * options of a decode the delegate accepted.
 */
internal class VectorSizeDecoderFactory(private val delegate: Decoder.Factory) : Decoder.Factory {
  override fun create(result: SourceFetchResult, options: Options, imageLoader: ImageLoader): Decoder? {
    val plain = delegate.create(result, options, imageLoader) ?: return null
    val target = options.getExtra(VectorTarget.KEY) ?: return plain
    return Decoder {
      // Resolved here, not in `create`: the view may not be laid out yet,
      // and only `decode` can wait for it.
      val atTarget = options.copy(size = target.size.size(), scale = target.scale)
      (delegate.create(result, atTarget, imageLoader) ?: plain).decode()
    }
  }
}
