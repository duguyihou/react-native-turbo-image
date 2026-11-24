package com.turboimage.loader

import android.graphics.Bitmap
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.turboimage.core.CachePolicy
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.Processing
import com.turboimage.core.ResizeMode
import com.turboimage.core.ResolvedRequest
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * What a load through the adapter does to its view and tells its listener:
 * the image at the size the request bounds it to, or a failure under one of
 * the seam's codes, and nothing at all after a cancel.
 */
@RunWith(AndroidJUnit4::class)
internal class LoadingTest : AdapterTest() {
  // MARK: Decode size

  @Test
  fun anImageLargerThanItsViewIsDecodedForTheView() {
    // 600×400 into 300×200: a half, exactly.
    val outcome = load(resolve(photo()))

    assertTrue(outcome.succeeded)
    assertEquals(VIEW_WIDTH to VIEW_HEIGHT, outcome.width to outcome.height)
    assertNotNull(outcome.view.drawable)
  }

  /**
   * `loadPlaceholder`: the image comes back sized for the view, and the
   * adapter leaves the view alone, because the view decides whether a
   * placeholder may still be shown.
   */
  @Test
  fun aPlaceholderLoadReturnsTheImageWithoutPaintingTheView() {
    val view = addView()
    val done = CountDownLatch(1)
    var drawable: Drawable? = null
    onMain {
      adapter.loadPlaceholder(view, resolve(photo())) {
        drawable = it
        done.countDown()
      }
    }
    assertTrue(done.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))

    onMain {
      assertNotNull(drawable)
      assertEquals(VIEW_WIDTH to VIEW_HEIGHT, drawable!!.intrinsicWidth to drawable!!.intrinsicHeight)
      assertNull("the view is the caller's", view.drawable)
    }
  }

  @Test
  fun withDownscalingOffTheImageKeepsItsSize() {
    val outcome = load(resolve(photo(), allowDownscaling = false))

    assertEquals(PHOTO_WIDTH to PHOTO_HEIGHT, outcome.width to outcome.height)
  }

  @Test
  fun decodingNeverUpscales() {
    val outcome = load(resolve(photo()), width = 4 * PHOTO_WIDTH, height = 4 * PHOTO_HEIGHT)

    assertEquals(PHOTO_WIDTH to PHOTO_HEIGHT, outcome.width to outcome.height)
  }

  /** `cover` needs the image to cover the view, so the shorter side binds. */
  @Test
  fun aViewTheImageMustCoverGetsMorePixelsThanOneItFitsInside() {
    // A 300×100 view: fitting inside it takes 150×100, covering it 300×200.
    val contained = load(resolve(photo(), resizeMode = ResizeMode.CONTAIN), width = 300, height = 100)
    val covering = load(resolve(photo(), resizeMode = ResizeMode.COVER), width = 300, height = 100)

    assertEquals(150 to 100, contained.width to contained.height)
    assertEquals(300 to 200, covering.width to covering.height)
  }

  /** `resize` in dp is a width in pixels, whatever the view's size. */
  @Test
  fun aResizeWidthBoundsTheDecode() {
    val outcome = load(resolve(photo(), processing = Processing(resize = 150.0)))

    assertEquals(150 to 100, outcome.width to outcome.height)
  }

  // MARK: Failures

  @Test
  fun anHttpErrorIsANetworkError() {
    val outcome = load(resolve("$BASE/no-such-route/${UUID.randomUUID()}.jpg"))

    assertEquals(LoadErrorCode.NETWORK, outcome.error)
    assertNull(outcome.view.drawable)
  }

  /**
   * An HTML error page sent with a 200 is the usual case. Android's
   * `ImageDecoder` reports it with an `IOException` subclass, which once
   * made this `network` on Android and `decode` on iOS.
   */
  @Test
  fun aBodyNoDecoderRecognisesIsADecodeError() {
    // 200 with the text "ok".
    val outcome = load(resolve(fixture("__ping")))

    assertEquals(outcome.message, LoadErrorCode.DECODE, outcome.error)
  }

  @Test
  fun aCacheMissUnderCacheOnlyIsNotCached() {
    val uri = photo()
    val outcome = load(resolve(uri, CachePolicy.CACHE_ONLY))

    assertEquals(LoadErrorCode.NOT_CACHED, outcome.error)
    assertEquals("cacheOnly must not reach the network", 0, requestsReceived(uri))
  }

  /**
   * A failed load paints nothing: what stays on screen (the previous image,
   * a placeholder) is the view's decision, made by the core's lifecycle.
   */
  @Test
  fun aFailedLoadLeavesTheViewsDrawableAlone() {
    val view = addView()
    val previous = ColorDrawable(0xff336699.toInt())
    onMain { view.setImageDrawable(previous) }

    val outcome = loadInto(view, resolve("$BASE/no-such-route/${UUID.randomUUID()}.jpg"))

    assertEquals(LoadErrorCode.NETWORK, outcome.error)
    assertSame(previous, view.drawable)
  }

  // MARK: Progress

  @Test
  fun progressIsReportedBeforeCompletionAndNeverAfter() {
    // Sent in 4 KB pieces with pauses, so several reads see progress.
    val outcome = load(resolve(photo("slow/photo"), CachePolicy.NO_CACHE))

    assertTrue(outcome.succeeded)
    assertTrue("expected progress callbacks, got none", outcome.progress.isNotEmpty())
    val (received, expected) = outcome.progress.last()
    assertTrue("progress ${outcome.progress} should end within the body", received <= expected)
    assertEquals(outcome.progress.map { it.first }.sorted(), outcome.progress.map { it.first })
    settle(200)
    assertFalse(outcome.progressAfterCompletion)
  }

  // MARK: Cancel

  /**
   * The seam's cancel contract carries more weight here than on iOS: the
   * adapter paints the view itself, so a load that outlives its cancel puts
   * a stale image on screen without the view having a say (ADR 0004).
   */
  @Test
  fun aCancelledLoadNeitherCompletesNorPaints() {
    val view = addView()
    val pending = start(view, resolve(photo("slow/photo"), CachePolicy.NO_CACHE))

    onMain { pending.handle.cancel() }

    // The slow photo takes about a third of a second when left alone.
    assertFalse("a cancelled load called back", pending.await(seconds = 2))
    assertNull(view.drawable)
    assertFalse(pending.outcome().completed)
  }

  @Test
  fun cancellingTwiceOrAfterCompletionIsHarmless() {
    val view = addView()
    val pending = start(view, resolve(photo()))
    assertTrue(pending.await())
    val shown = view.drawable

    onMain {
      pending.handle.cancel()
      pending.handle.cancel()
    }

    assertSame("cancelling a finished load must not clear the view", shown, view.drawable)
  }

  // MARK: Prefetch

  @Test
  fun prefetchReportsWhetherTheImageLoaded() {
    assertTrue(prefetch(resolve(photo(), allowDownscaling = false)))
    assertFalse(prefetch(resolve("$BASE/no-such-route/${UUID.randomUUID()}.jpg", allowDownscaling = false)))
  }

  @Test
  fun aPrefetchedImageNeedsNoNetwork() {
    val uri = photo()
    assertTrue(prefetch(resolve(uri, allowDownscaling = false)))

    assertTrue(isCached(uri))
    assertEquals(1, requestsReceived(uri))
  }

  /**
   * A prefetch (memory write off): the bytes
   * reach the disk and no decoded bitmap is kept. Before, a prefetch decoded
   * the full-size image under the key unprocessed views share, so a list
   * thumbnail was then drawn from that bitmap.
   */
  @Test
  fun aDiskOnlyPrefetchStoresTheBytesAndNoBitmap() {
    val uri = photo()
    val request = resolve(uri, allowDownscaling = false).copy(memoryWrite = false)
    assertTrue(prefetch(request))

    assertNull("nothing in memory", memoryCached(request))
    assertTrue(isCached(uri))
    assertEquals(1, requestsReceived(uri))
  }

  @Test
  fun aDiskOnlyPrefetchStillReportsAFailure() {
    val request = resolve("$BASE/no-such-route/${UUID.randomUUID()}.jpg", allowDownscaling = false)
    assertFalse(prefetch(request.copy(memoryWrite = false)))
  }

  // MARK: Headers

  @Test
  fun requestHeadersAreSent() {
    // The route answers 406 unless `Accept` allows PNG.
    val refused = load(resolve(fixture("accept/png"), headers = listOf("Accept" to "image/jpeg")))
    val accepted = load(resolve(fixture("accept/png"), headers = listOf("Accept" to "image/png")))

    assertEquals(LoadErrorCode.NETWORK, refused.error)
    assertTrue(accepted.succeeded)
  }

  // MARK: Image size (`TurboImage.getSize`)

  /** `imageSize`, as the cache module calls it: (width, height) or the error code. */
  private fun sizeOf(request: ResolvedRequest): Pair<Pair<Int, Int>?, LoadErrorCode?> {
    val done = CountDownLatch(1)
    var size: Pair<Int, Int>? = null
    var error: LoadErrorCode? = null
    onMain {
      adapter.imageSize(
        request,
        onSize = { width, height ->
          size = width to height
          done.countDown()
        },
        onError = { code, _ ->
          error = LoadErrorCode.entries.first { it.nativeValue == code }
          done.countDown()
        },
      )
    }
    assertTrue(done.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))
    return size to error
  }

  /** The module's request: the original, no view to size it for. */
  private fun moduleRequest(uri: String) = resolve(uri, allowDownscaling = false)

  @Test
  fun theSizeIsTheImagesOwnInPixels() {
    assertEquals(PHOTO_WIDTH to PHOTO_HEIGHT, sizeOf(moduleRequest(photo())).first)
    assertEquals(3000 to 2000, sizeOf(moduleRequest(fixture("large/size.jpg"))).first)
  }

  @Test
  fun theSizeFollowsTheExifOrientation() {
    // 60x40 pixels, stored with orientation 6: shown 40x60.
    val file = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "rotated-${UUID.randomUUID()}.jpg")
    file.outputStream().use {
      Bitmap.createBitmap(60, 40, Bitmap.Config.ARGB_8888)
        .compress(Bitmap.CompressFormat.JPEG, 90, it)
    }
    ExifInterface(file.absolutePath).apply {
      setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_ROTATE_90.toString())
      saveAttributes()
    }

    assertEquals(40 to 60, sizeOf(moduleRequest("file://${file.absolutePath}")).first)
  }

  @Test
  fun aBodyThatIsNotAnImageFailsAsADecodeError() {
    assertEquals(LoadErrorCode.DECODE, sizeOf(moduleRequest(fixture("not-an-image/size"))).second)
  }
}
