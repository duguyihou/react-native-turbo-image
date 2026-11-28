package com.turboimage.loader

import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.media.ExifInterface
import coil3.ImageLoader
import coil3.decode.DecodeResult
import coil3.decode.Decoder
import coil3.fetch.SourceFetchResult
import coil3.request.Options

// `TurboImage.getSize`: Coil has no "fetch without decoding", so this decoder
// reads only the header size instead of decoding a full bitmap.

/** A size with no pixels; never drawn or cached. */
internal class SizeOnlyImage(override val width: Int, override val height: Int) : coil3.Image {
  override val size: Long = 0
  override val shareable: Boolean = false

  override fun draw(canvas: Canvas) = Unit
}

/**
 * Reads a bitmap's header size, EXIF-oriented. Other formats (SVG) fall back
 * to a full decode, matching the size iOS reports.
 */
internal class HeaderSizeDecoder(
  private val result: SourceFetchResult,
  private val options: Options,
  private val imageLoader: ImageLoader,
) : Decoder {
  override suspend fun decode(): DecodeResult {
    headerSize()?.let { (width, height) -> return DecodeResult(SizeOnlyImage(width, height), isSampled = false) }
    val delegate =
      imageLoader.components.newDecoder(result, options, imageLoader)?.first
        ?: throw IllegalStateException("No decoder recognises this image")
    return delegate.decode() ?: throw IllegalStateException("The image could not be decoded")
  }

  /** Oriented (width, height), or null if BitmapFactory can't read the header. */
  private fun headerSize(): Pair<Int, Int>? {
    // Peek, so a fallback decode still starts at byte 0.
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    result.source.source().peek().inputStream().use { BitmapFactory.decodeStream(it, null, bounds) }
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
    val orientation =
      runCatching {
          result.source.source().peek().inputStream().use {
            ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
          }
        }
        .getOrDefault(ExifInterface.ORIENTATION_NORMAL)
    val turned =
      orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
        orientation == ExifInterface.ORIENTATION_ROTATE_270 ||
        orientation == ExifInterface.ORIENTATION_TRANSPOSE ||
        orientation == ExifInterface.ORIENTATION_TRANSVERSE
    return if (turned) bounds.outHeight to bounds.outWidth else bounds.outWidth to bounds.outHeight
  }

  class Factory : Decoder.Factory {
    override fun create(result: SourceFetchResult, options: Options, imageLoader: ImageLoader): Decoder =
      HeaderSizeDecoder(result, options, imageLoader)
  }
}
