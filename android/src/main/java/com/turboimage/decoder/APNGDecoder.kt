package com.turboimage.decoder

import coil.ImageLoader
import coil.decode.DecodeResult
import coil.decode.Decoder
import coil.decode.ImageSource
import coil.fetch.SourceResult
import coil.request.Options
import com.github.penfeizhou.animation.apng.APNGDrawable
import com.github.penfeizhou.animation.apng.decode.APNGParser

class APNGDecoder(private val source: ImageSource) : Decoder {

  override suspend fun decode(): DecodeResult {
    return DecodeResult(
      drawable = APNGDrawable.fromFile(source.file().toString()),
      isSampled = false
    )
  }

  class Factory : Decoder.Factory {

    override fun create(result: SourceResult, options: Options, imageLoader: ImageLoader): Decoder? {
      if (APNGParser.isAPNG(result.source.file().toString())) {
        return APNGDecoder(result.source)
      }
      return null
    }
  }
}
