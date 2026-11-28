package com.turboimage.core

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * [TurboImageCore.process] across JNI: pixels reach the core and come back in
 * place, whatever the input's config. The maths is tested in C++.
 */
@RunWith(AndroidJUnit4::class)
class ProcessingTest {
  /** An opaque row of red over a transparent row, 3 px wide (odd on purpose). */
  private fun redOverClear(config: Bitmap.Config = Bitmap.Config.ARGB_8888): Bitmap {
    val bitmap = Bitmap.createBitmap(3, 2, Bitmap.Config.ARGB_8888)
    for (x in 0 until 3) {
      bitmap.setPixel(x, 0, Color.RED)
      bitmap.setPixel(x, 1, Color.TRANSPARENT)
    }
    return if (config == Bitmap.Config.ARGB_8888) bitmap else bitmap.copy(config, false)
  }

  private fun processorKey(processing: Processing): String {
    val resolved = TurboImageCore.resolve(ImageRequest(uri = URL, processing = processing), 1.0)
    return (resolved as ResolvedRequest).processorKey
  }

  private fun rows(bitmap: Bitmap): List<List<Int>> =
    (0 until bitmap.height).map { y -> (0 until bitmap.width).map { x -> bitmap.getPixel(x, y) } }

  @Test
  fun everyPixelComesBackInItsPlace() {
    val input = redOverClear()

    val output = TurboImageCore.process(input, processorKey(Processing(tint = Color.BLUE)))

    assertNotNull(output)
    assertEquals(Bitmap.Config.ARGB_8888, output!!.config)
    // Tint keeps alpha: the opaque row turns blue, the clear row stays clear.
    assertEquals(
      listOf(List(3) { Color.BLUE }, List(3) { Color.TRANSPARENT }),
      rows(output),
    )
  }

  @Test
  fun theInputIsLeftAsItWas() {
    val input = redOverClear()

    val output = TurboImageCore.process(input, processorKey(Processing(tint = Color.BLUE)))

    assertNotSame(input, output)
    assertEquals(List(3) { Color.RED }, rows(input)[0])
  }

  @Test
  fun anotherConfigIsConvertedFirst() {
    // RGB_565 has no alpha, so both rows come out opaque: red and black.
    val input = redOverClear(Bitmap.Config.RGB_565)

    val output = TurboImageCore.process(input, processorKey(Processing(tint = Color.BLUE)))

    assertEquals(List(3) { Color.BLUE }, rows(output!!)[0])
  }

  @Test
  fun aResizeReturnsABitmapOfTheNewSize() {
    val input = Bitmap.createBitmap(300, 200, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) }

    val output = TurboImageCore.process(input, processorKey(Processing(resize = 150.0)))

    assertEquals(150 to 100, output!!.width to output.height)
    assertEquals(Color.RED, output.getPixel(149, 99))
  }

  @Test
  fun anInvalidKeyGivesNothing() {
    assertNull(TurboImageCore.process(redOverClear(), "not a processor key"))
  }

  private companion object {
    // Never fetched: only the processor key is used.
    const val URL = "https://images.example.com/photos/harbour.jpg"
  }
}
