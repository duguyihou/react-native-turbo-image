package com.turboimage.loader

import android.content.Context
import android.graphics.Bitmap
import android.graphics.drawable.Animatable
import android.graphics.drawable.Drawable
import android.graphics.drawable.DrawableWrapper
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
import coil3.transition.CrossfadeDrawable
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

// Translates a resolved request into a Coil request, plus the Coil extension
// points it uses (target, transformation, size resolver, vector decoder).

/**
 * Mechanical translation; the core already decided policy, keys and size.
 * [view] is null for a prefetch.
 */
internal fun ResolvedRequest.toCoilRequest(context: Context, view: View?): ImageRequest.Builder =
  ImageRequest.Builder(context)
    .data(url)
    .memoryCacheKey(cacheKey)
    .apply {
      // An explicit memory key has no size, so tag original-size entries
      // with Coil's size extra to keep them apart from view-sized ones.
      // A processed SVG also keys by its vector size, or views of different
      // sizes would share one drawing. Trade-off: an unprocessed one does not.
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
      // Read by PolicyCacheStrategy to apply HTTP freshness.
      if (httpCache) extras[PolicyCacheStrategy.HTTP_CACHE] = true
      applyDecodeSize(decode, view)
      // Only the decoder knows it's an SVG, so the vector size travels as an
      // extra for VectorSizeDecoderFactory.
      if (vectorDecode != decode) {
        vectorTarget(vectorDecode, view)?.let { extras[VectorTarget.KEY] = it }
      }
      if (processorKey.isNotEmpty()) {
        transformations(CoreProcessingTransformation(processorKey))
      }
    }

/**
 * Coil's internal memory-key extra for an entry's size (3.6.3).
 * `CacheTest.anOriginalSizeSvgIsServedFromMemory` catches a rename.
 */
internal const val COIL_SIZE_EXTRA = "coil#size"

/** The size a processed vector is drawn at, when that is not the decode's. */
private const val VECTOR_SIZE_EXTRA = "turboimage#vector"

/** [vector] as a key part, in pixels; null if the view has no size yet. */
private fun vectorKey(vector: ResolvedRequest.DecodeSize, view: View?): String? =
  when (vector) {
    ResolvedRequest.DecodeSize.Original -> ""
    is ResolvedRequest.DecodeSize.Width -> "w=${vector.pixels}"
    is ResolvedRequest.DecodeSize.View ->
      view?.takeIf { it.width > 0 && it.height > 0 }?.let {
        "${it.width}x${it.height}" + if (vector.fill) ",fill" else ""
      }
  }

/** The core's decode target as Coil sizing (sampled while decoding). */
private fun ImageRequest.Builder.applyDecodeSize(decode: ResolvedRequest.DecodeSize, view: View?) {
  when (decode) {
    ResolvedRequest.DecodeSize.Original -> size(Size.ORIGINAL)
    is ResolvedRequest.DecodeSize.View -> {
      // No view (prefetch): no bound. The core never asks for this anyway.
      if (view != null) size(LaidOutSizeResolver(view)) else size(Size.ORIGINAL)
      scale(if (decode.fill) Scale.FILL else Scale.FIT)
    }
    is ResolvedRequest.DecodeSize.Width -> {
      size(Dimension(decode.pixels), Dimension.Undefined)
      scale(Scale.FIT)
    }
  }
  // Targets are upper bounds; EXACT would upscale smaller images.
  precision(Precision.INEXACT)
}

/** The vector target, or null for the SVG's own size. */
private fun vectorTarget(decode: ResolvedRequest.DecodeSize, view: View?): VectorTarget? =
  when (decode) {
    ResolvedRequest.DecodeSize.Original -> null
    // A prefetch has no view.
    is ResolvedRequest.DecodeSize.View ->
      view?.let { VectorTarget(LaidOutSizeResolver(it), if (decode.fill) Scale.FILL else Scale.FIT) }
    is ResolvedRequest.DecodeSize.Width ->
      VectorTarget(SizeResolver(Size(Dimension(decode.pixels), Dimension.Undefined)), Scale.FIT)
  }

/** HTTP-cache entries share the DiskCache under their own URL-keyed prefix. */
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
 * Sets only the loaded image; Coil's default would wipe our placeholder on
 * start and error (RFC rule 3). Subclassed to keep Coil's detach/attach
 * cancel/restart.
 */
internal class KeepCurrentImageTarget(view: ImageView) : ImageViewTarget(view) {
  override fun onStart(placeholder: Image?) = Unit

  override fun onError(error: Image?) = Unit

  // Every image Coil shows, faded or not, is set through here.
  override var drawable: Drawable?
    get() = super.drawable
    set(value) {
      super.drawable = if (value is CrossfadeDrawable) SizedAsItsEnd(value) else value
    }
}

/**
 * A cross-fade that reports the size of the image it fades to.
 *
 * `CrossfadeDrawable` fixes its intrinsic size when it is built, at the
 * larger of the two images in each dimension, and stays the view's drawable
 * after the fade. The view places a drawable by its intrinsic size, so a
 * landscape image fading in over a portrait one was drawn in a square box
 * (too small under `contain`, zoomed under `cover`), stayed so, and the next
 * fade inherited the box. Sized as its end, the new image is placed exactly;
 * the old one is fitted or cropped into that box (Coil's `scale`) for the
 * length of the fade only.
 */
private class SizedAsItsEnd(private val crossfade: CrossfadeDrawable) : DrawableWrapper(crossfade), Animatable {
  override fun getIntrinsicWidth() = crossfade.end?.intrinsicWidth ?: -1

  override fun getIntrinsicHeight() = crossfade.end?.intrinsicHeight ?: -1

  // Coil starts the fade (and an animated end) through `Animatable`.
  override fun start() = crossfade.start()

  override fun stop() = crossfade.stop()

  override fun isRunning() = crossfade.isRunning
}

/**
 * The core's processing as a Coil transformation. Variants get their own
 * memory entries; the disk keeps one original. A throw is a `decode` error.
 */
private class CoreProcessingTransformation(private val processorKey: String) : Transformation() {
  override val cacheKey: String = processorKey

  override suspend fun transform(input: Bitmap, size: Size): Bitmap =
    TurboImageCore.process(input, processorKey)
      ?: throw IllegalStateException("TurboImage processing failed ($processorKey)")
}

/**
 * The view's laid-out size in pixels. Not Coil's `ViewSizeResolver`: Fabric
 * leaves `WRAP_CONTENT` params, which Coil treats as unbounded.
 *
 * Waits for the first layout, or one main-loop turn: a view re-attached by
 * `removeClippedSubviews` may never get another layout pass. `View.post` runs
 * after attach, so a new view's first layout still lands first. An empty
 * view gets the original, as on iOS.
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
    /** Absent when the request's size is the vector's too. */
    val KEY = Extras.Key<VectorTarget?>(default = null)
  }
}

/**
 * Draws a vector at its [VectorTarget]. With `allowDownscaling={false}`
 * Coil asks for `Size.ORIGINAL`, which for an SVG is often smaller than the
 * view; only the decoder knows the bytes are an SVG, so the size swaps here.
 */
internal class VectorSizeDecoderFactory(private val delegate: Decoder.Factory) : Decoder.Factory {
  override fun create(result: SourceFetchResult, options: Options, imageLoader: ImageLoader): Decoder? {
    val plain = delegate.create(result, options, imageLoader) ?: return null
    val target = options.getExtra(VectorTarget.KEY) ?: return plain
    return Decoder {
      // Resolved here: only `decode` can wait for layout.
      val atTarget = options.copy(size = target.size.size(), scale = target.scale)
      (delegate.create(result, atTarget, imageLoader) ?: plain).decode()
    }
  }
}
