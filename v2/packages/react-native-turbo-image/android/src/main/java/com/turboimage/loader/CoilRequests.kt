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
    .apply {
      // An explicit `memoryCacheKey` carries no size, so Coil judges an entry
      // by its pixels alone. That shared one entry between original-size and
      // view-sized loads of a key: after an original-size load (a `'memory'`
      // prefetch, `center`, `allowDownscaling={false}`) thumbnails were drawn
      // from the full-size bitmap. And an SVG is a "sampled" bitmap, which
      // Coil never accepts for `Size.ORIGINAL`, so original-size SVGs were
      // drawn again from the disk on every load. With Coil's own size extra,
      // original-size entries are separate and matched exactly, as Nuke's
      // keys (no `thumbnail`) are on iOS.
      //
      //
      // Under `allowDownscaling={false}` an SVG is drawn at `vectorDecode`
      // (the view's size, or `resize`'s width), not at the original. A
      // processed one puts that size in the key, as iOS's `processorID`
      // does, or views of different sizes would share one processed drawing
      // (the smoke suite's `svgFullSizeTintedSmaller`). Before the view has a
      // size there is none to put in, so such a request keeps the plain key
      // and is drawn again, as before. Known trade-off: an *unprocessed*
      // opt-out SVG keeps the shared key, so two views of it at different
      // sizes share the first one's drawing; on iOS it stays a vector.
      if (decode == ResolvedRequest.DecodeSize.Original) {
        val vectorKey = if (processorKey.isEmpty() || vectorDecode == decode) "" else vectorKey(vectorDecode, view)
        if (vectorKey != null) {
          memoryCacheKeyExtra(COIL_SIZE_EXTRA, Size.ORIGINAL.toString())
          if (vectorKey.isNotEmpty()) memoryCacheKeyExtra(VECTOR_SIZE_EXTRA, vectorKey)
        }
      }
    }
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
 * The memory-key extra under which Coil records the size an entry was
 * resolved for, and which `MemoryCacheService.isCacheValueValidForSize`
 * compares with a request's size before anything else. Coil's own name,
 * internal to it (3.6.3); `CacheTest.anOriginalSizeSvgIsServedFromMemory`
 * fails if it changes.
 */
internal const val COIL_SIZE_EXTRA = "coil#size"

/** The size a processed vector is drawn at, when that is not the decode's. */
private const val VECTOR_SIZE_EXTRA = "turboimage#vector"

/**
 * [vector] as a key part, in whole pixels like iOS's `processorID`; null when
 * it is the view's size and the view has none yet.
 */
private fun vectorKey(vector: ResolvedRequest.DecodeSize, view: View?): String? =
  when (vector) {
    ResolvedRequest.DecodeSize.Original -> ""
    is ResolvedRequest.DecodeSize.Width -> "w=${vector.pixels}"
    is ResolvedRequest.DecodeSize.View ->
      view?.takeIf { it.width > 0 && it.height > 0 }?.let {
        "${it.width}x${it.height}" + if (vector.fill) ",fill" else ""
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
 * still sees its real size. That holds for a preallocated view too, whose
 * props (and so its load) can come several main-loop turns before its
 * mount: `View.post` keeps the fallback until the view is attached, and
 * attaching posts it, after the batch that lays the view out (a post to the
 * main handler would run too early). Checked with a temporary log on
 * 2026-11-24: no wait ended in `Size.ORIGINAL` across the smoke suite and
 * the bench's `load` and FlashList `grid` scenarios (about 2,000 waits).
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
