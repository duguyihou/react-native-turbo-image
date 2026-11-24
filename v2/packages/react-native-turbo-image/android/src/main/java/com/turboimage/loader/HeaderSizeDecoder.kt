package com.turboimage.loader

import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.media.ExifInterface
import coil3.ImageLoader
import coil3.decode.DecodeResult
import coil3.decode.Decoder
import coil3.fetch.SourceFetchResult
import coil3.request.Options

// `TurboImage.getSize` on Android: the Coil request runs as usual (fetch,
// disk cache), but this decoder reads only the size from the file's header,
// so a 12 MP photo costs a download, not a 48 MB bitmap. Coil has no
// "fetch without decoding", hence a decoder that answers with a size.

/**
 * An image with a size and no pixels: what [HeaderSizeDecoder] returns.
 * Never drawn and never cached (the request disables memory writes).
 */
internal class SizeOnlyImage(override val width: Int, override val height: Int) : coil3.Image {
  override val size: Long = 0
  override val shareable: Boolean = false

  override fun draw(canvas: Canvas) = Unit
}

/**
 * Reads the size of a bitmap format Android can bound (JPEG, PNG, WebP, GIF,
 * HEIF and AVIF where the OS decodes them) and turns it by the EXIF
 * orientation, as a decode would. Anything else (SVG) goes to the loader's
 * own decoders, in full, and reports the size they draw it at: for an SVG,
 * its canvas at the screen's density (`scaleToDensity`, CoilLoaderSetup.kt),
 * which is what iOS reports too.
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

  /** (width, height) in pixels after the orientation, or null when the header is not one BitmapFactory reads. */
  private fun headerSize(): Pair<Int, Int>? {
    // Peeks, so a fallback to a full decode still reads the bytes from the start.
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
