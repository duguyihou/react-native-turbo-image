package com.turboimage.loader

import coil3.ImageLoader
import coil3.asImage
import coil3.decode.DecodeResult
import coil3.decode.Decoder
import coil3.fetch.SourceFetchResult
import coil3.request.Options
import com.linecorp.apng.ApngDrawable
import kotlinx.coroutines.runInterruptible
import okio.BufferedSource
import okio.ByteString.Companion.encodeUtf8
import okio.ByteString.Companion.toByteString

/**
 * Animated PNG for Coil 3. Android's ImageDecoder animates GIF, WebP and
 * HEIF but shows only the first frame of an APNG, so 1.x used LINE's
 * `com.linecorp:apng` and so does 2.0 (iOS gets APNG from ImageIO).
 * Registered ahead of Coil's bitmap decoder; static PNGs fall through to it.
 */
internal class ApngDecoder(private val result: SourceFetchResult) : Decoder {

  override suspend fun decode(): DecodeResult = runInterruptible {
    val drawable = result.source.source().inputStream().use { ApngDrawable.decode(it) }
    // Coil's ImageViewTarget starts Animatable drawables when shown.
    DecodeResult(image = drawable.asImage(), isSampled = false)
  }

  class Factory : Decoder.Factory {
    override fun create(result: SourceFetchResult, options: Options, imageLoader: ImageLoader): Decoder? =
      if (isApng(result.source.source())) ApngDecoder(result) else null
  }

  companion object {
    private val PNG_SIGNATURE = byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10).toByteString()
    private val ACTL = "acTL".encodeUtf8()
    private val IDAT = "IDAT".encodeUtf8()

    /**
     * The APNG spec requires `acTL` before the first `IDAT`, so walking the
     * chunk headers up to `IDAT` decides it. Uses `peek()`, so the source is
     * not consumed for the decoder that runs next.
     */
    fun isApng(source: BufferedSource): Boolean {
      val peek = source.peek()
      return try {
        if (!peek.rangeEquals(0, PNG_SIGNATURE)) return false
        peek.skip(PNG_SIGNATURE.size.toLong())
        while (true) {
          val length = peek.readInt().toLong() and 0xffffffffL
          val type = peek.readByteString(4)
          when (type) {
            ACTL -> return true
            IDAT -> return false
          }
          peek.skip(length + 4) // data + CRC
        }
        @Suppress("UNREACHABLE_CODE") false
      } catch (_: java.io.IOException) {
        false // truncated or not a PNG
      }
    }
  }
}
