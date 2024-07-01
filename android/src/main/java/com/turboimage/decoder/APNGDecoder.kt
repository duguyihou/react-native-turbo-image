package com.turboimage.decoder

import coil.decode.DecodeResult
import coil.decode.Decoder
import coil.decode.ImageSource
import com.linecorp.apng.ApngDrawable
import kotlinx.coroutines.runInterruptible




class APNGDecoder(private val source: ImageSource) : Decoder {

  override suspend fun decode() = runInterruptible {
    val isAPNG =ApngDrawable.isApng(source.file().toString())

    if(isAPNG){
      DecodeResult(drawable = ApngDrawable.decode(source.file().toString()), isSampled = false)
    } else {
      null
    }
  }
}
