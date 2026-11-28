package com.turboimage

import android.content.res.Resources
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.graphics.Matrix
import android.view.View
import android.widget.ImageView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.facebook.react.bridge.BridgeReactContext
import com.facebook.react.bridge.JavaOnlyMap
import com.facebook.react.uimanager.ThemedReactContext
import com.turboimage.core.ImageRequest
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.Processing
import com.turboimage.core.ResolvedRequest
import com.turboimage.loader.ImageLoaderAdapter
import com.turboimage.loader.LoadHandle
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * `TurboImageView` against a [FakeLoader] and the real core: when it loads,
 * what it asks for, and which events JS hears. Runs on the main thread with
 * no window; `layout()` stands in for Fabric setting the frame.
 *
 * TODO: hash placeholders, `recyclingKey` and progress.
 */
@RunWith(AndroidJUnit4::class)
class TurboImageViewTest {
  private val instrumentation = InstrumentationRegistry.getInstrumentation()
  private lateinit var loader: FakeLoader
  private lateinit var view: TurboImageView
  // Drives the host lifecycle the view listens to (pause = background).
  private lateinit var host: BridgeReactContext
  private val events = mutableListOf<Pair<String, JavaOnlyMap>>()

  @Before
  fun makeView() = onMain {
    val context = instrumentation.targetContext
    loader = FakeLoader()
    host = BridgeReactContext(context)
    view = TurboImageView(ThemedReactContext(host, context, null, -1), loader)
    view.eventSink = { name, payload -> events += name to JavaOnlyMap().apply(payload) }
  }

  // MARK: Upgrades

  @Test
  fun aViewThatGrowsPastHalfAgainLoadsItsImageAgainSilently() = onMain {
    showLoadedImage()
    val shown = view.drawable

    resize(600, 400)

    assertEquals("an upgrade starts", 2, loader.loads.size)
    val upgrade = loader.loads[1]
    assertEquals("for the same image", loader.loads[0].request, upgrade.request)
    assertEquals("without a cross-fade", 0, upgrade.options.fadeMillis)
    assertSame("the image stays while it loads", shown, view.drawable)

    upgrade.succeed(600, 400)

    assertNotSame(shown, view.drawable)
    assertEquals("JS hears nothing", emptyList<String>(), eventNames())
  }

  // An upgrade would restart the animation; iOS skips them too.
  @Test
  fun anAnimatedImageIsNeverLoadedAgain() = onMain {
    showLoadedImage(animated = true)

    resize(900, 600)

    assertEquals(1, loader.loads.size)
  }

  @Test
  fun growingByHalfOrLessKeepsTheImage() = onMain {
    showLoadedImage()

    resize(450, 300) // exactly 1.5x

    assertEquals(1, loader.loads.size)
  }

  @Test
  fun anImageSmallerThanItsViewIsNeverLoadedAgain() = onMain {
    // Decoding never upscales, so a larger view would get the same pixels.
    showLoadedImage(decodedWidth = 100, decodedHeight = 50)

    resize(900, 600)

    assertEquals(1, loader.loads.size)
  }

  @Test
  fun anImageNotDecodedForTheViewIsNeverLoadedAgain() = onMain {
    // With downscaling off, the decode ignores the view's size.
    showLoadedImage(request = ImageRequest(uri = URL, allowDownscaling = false))

    resize(900, 600)

    assertEquals(1, loader.loads.size)
  }

  @Test
  fun aViewThatGrewDuringItsLoadUpgradesWhenTheLoadSucceeds() = onMain {
    resize(300, 200)
    setSource(URL)

    resize(600, 400)
    assertEquals("no upgrade beside a load", 1, loader.loads.size)

    loader.loads[0].succeed(300, 200)

    assertEquals(2, loader.loads.size)
  }

  @Test
  fun anUpgradedImageCanBeUpgradedAgain() = onMain {
    showLoadedImage()
    resize(600, 400)
    loader.loads[1].succeed(600, 400)

    resize(1200, 800)

    assertEquals(3, loader.loads.size)
  }

  @Test
  fun aFailedUpgradeKeepsTheImageAndIsNotRetried() = onMain {
    showLoadedImage()
    val shown = view.drawable
    resize(600, 400)

    loader.loads[1].fail()
    resize(1200, 800)

    assertSame(shown, view.drawable)
    assertEquals("no second attempt for this image", 2, loader.loads.size)
    assertEquals(emptyList<String>(), eventNames())
  }

  @Test
  fun aNewSourceCancelsAnUpgradeWithoutAnEvent() = onMain {
    showLoadedImage()
    resize(600, 400)
    val upgrade = loader.loads[1]

    setSource("$URL?other")

    assertTrue("the upgrade is cancelled", upgrade.cancelled)
    // JS never saw the upgrade, so it gets no onCompletion for it.
    assertEquals(listOf("topStart"), eventNames())
    assertEquals(3, loader.loads.size)

    // A callback after cancel (a seam violation) must be ignored.
    events.clear()
    upgrade.listener.onSuccess(600, 400, false)
    assertEquals(emptyList<String>(), eventNames())
  }

  @Test
  fun droppingTheViewCancelsAnUpgradeWithoutAnEvent() = onMain {
    showLoadedImage()
    resize(600, 400)

    view.drop()

    assertTrue(loader.loads[1].cancelled)
    assertEquals(emptyList<String>(), eventNames())
  }

  // MARK: Image placeholders

  private fun setSourceWithThumbnail() {
    resize(300, 200)
    view.placeholderUri = THUMB_URL
    view.request = ImageRequest(uri = URL)
    view.onTransactionEnd()
  }

  @Test
  fun anImagePlaceholderShowsWhileTheImageLoads() = onMain {
    setSourceWithThumbnail()
    val thumb = loader.placeholderLoads.single()
    assertEquals(THUMB_URL, thumb.request.url)

    thumb.deliver(SizedDrawable(30, 20))

    assertEquals(30, view.drawable.intrinsicWidth)
    loader.loads.single().succeed(300, 200)
    assertEquals(300, view.drawable.intrinsicWidth)
    assertEquals("no events of its own", listOf("topStart", "topSuccess", "topCompletion"), eventNames())
  }

  @Test
  fun aPlaceholderThatArrivesLateIsNotShownOverTheImage() = onMain {
    setSourceWithThumbnail()
    val thumb = loader.placeholderLoads.single()
    loader.loads.single().succeed(300, 200)

    assertTrue("no longer needed", thumb.cancelled)
    // A callback after cancel (a seam violation) must not win.
    thumb.deliver(SizedDrawable(30, 20))

    assertEquals(300, view.drawable.intrinsicWidth)
  }

  // Only `showPlaceholderOnFailure` changes, after the failure: no reload runs.
  @Test
  fun turningOffShowPlaceholderOnFailureClearsTheKeptPlaceholder() = onMain {
    view.showPlaceholderOnFailure = true
    setSourceWithThumbnail()
    loader.placeholderLoads.single().deliver(SizedDrawable(30, 20))
    loader.loads.single().fail(LoadErrorCode.DECODE)
    assertEquals("kept over the failure", 30, view.drawable.intrinsicWidth)

    view.showPlaceholderOnFailure = false
    view.onTransactionEnd()

    assertNull(view.drawable)
  }

  @Test
  fun turningOnShowPlaceholderOnFailureShowsThePlaceholderOverTheFailure() = onMain {
    setSourceWithThumbnail()
    loader.loads.single().fail(LoadErrorCode.DECODE)
    assertNull(view.drawable)

    view.showPlaceholderOnFailure = true
    view.onTransactionEnd()

    assertEquals("the placeholder loads again", 2, loader.placeholderLoads.size)
    loader.placeholderLoads.last().deliver(SizedDrawable(30, 20))
    assertEquals(30, view.drawable.intrinsicWidth)
    assertEquals("the image's own load is not restarted", 1, loader.loads.size)
  }

  // The source's credentials must not reach a third-party host.
  @Test
  fun anImagePlaceholderOnAnotherHostGetsNoHeaders() = onMain {
    resize(300, 200)
    view.placeholderUri = "https://thumbs.cdn-vendor.com/harbour.jpg"
    view.request = ImageRequest(uri = URL, headers = listOf("Authorization" to "Bearer t0ken"))
    view.onTransactionEnd()

    assertEquals(emptyList<Pair<String, String>>(), loader.placeholderLoads.single().request.headers)
    assertEquals("the source keeps its headers", 1, loader.loads.single().request.headers.size)
  }

  @Test
  fun anImagePlaceholderUsesTheSourcesHeadersAndNoProcessing() = onMain {
    resize(300, 200)
    view.placeholderUri = THUMB_URL
    view.request =
      ImageRequest(uri = URL, headers = listOf("Authorization" to "Bearer t0ken"), processing = Processing(blur = 8.0))
    view.onTransactionEnd()

    val thumb = loader.placeholderLoads.single().request
    assertEquals(listOf("Authorization" to "Bearer t0ken"), thumb.headers)
    assertEquals("", thumb.processorKey)
    assertTrue(loader.loads.single().request.processorKey.isNotEmpty())
  }

  // MARK: Load events

  @Test
  fun aViewWithNoHandlersSendsNoLoadEvents() = onMain {
    view.loadEventMask = 0
    resize(300, 200)
    setSource(URL)
    loader.loads.single().succeed(300, 200)

    assertEquals(emptyList<String>(), eventNames())
  }

  @Test
  fun onlyTheHandledEventsAreSent() = onMain {
    view.loadEventMask = 4 or 8 // onFailure, onCompletion
    resize(300, 200)
    setSource(URL)
    loader.loads.single().fail()

    assertEquals(listOf("topFailure", "topCompletion"), eventNames())
  }

  /** The mask is read per event, not once per load. */
  @Test
  fun aHandlerAddedMidLoadHearsTheRestOfIt() = onMain {
    view.loadEventMask = 0
    resize(300, 200)
    setSource(URL)

    view.loadEventMask = 8 // onCompletion
    loader.loads.single().succeed(300, 200)

    assertEquals(listOf("topCompletion"), eventNames())
  }

  // MARK: contentPosition

  /** The image matrix as (scaleX, scaleY, translateX, translateY). */
  private fun drawMatrix(): List<Float> {
    val values = FloatArray(9)
    view.imageMatrix.getValues(values)
    return listOf(values[Matrix.MSCALE_X], values[Matrix.MSCALE_Y], values[Matrix.MTRANS_X], values[Matrix.MTRANS_Y])
  }

  @Test
  fun aPositionedCoverDrawsInTheCoresRectangle() = onMain {
    resize(200, 100)
    view.setResizeMode("cover")
    view.contentPositionY = 1.0 // bottom
    view.request = view.request.copy(uri = URL)
    view.onTransactionEnd()

    // 50x50 covering 200x100: scaled 4x to 200x200, its bottom 100 shown.
    loader.loads.single().succeed(50, 50)

    assertEquals(ImageView.ScaleType.MATRIX, view.scaleType)
    assertEquals(listOf(4f, 4f, 0f, -100f), drawMatrix())
  }

  @Test
  fun aCentredPositionKeepsThePlatformsScaleType() = onMain {
    resize(200, 100)
    view.setResizeMode("cover")
    view.contentPositionY = 1.0
    view.contentPositionY = 0.5
    view.request = view.request.copy(uri = URL)
    view.onTransactionEnd()
    loader.loads.single().succeed(50, 50)

    assertEquals(ImageView.ScaleType.CENTER_CROP, view.scaleType)
  }

  // MARK: Retry after a network failure

  @Test
  fun aNetworkFailureRetriesWhenTheAppReturnsWithFreshEvents() = onMain {
    resize(300, 200)
    setSource(URL)
    loader.loads[0].fail()
    events.clear()

    host.onHostPause()
    assertEquals("nothing retries in the background", 1, loader.loads.size)
    host.onHostResume(null)

    assertEquals(2, loader.loads.size)
    assertEquals(loader.loads[0].request, loader.loads[1].request)
    loader.loads[1].succeed(300, 200)
    assertEquals(listOf("topStart", "topSuccess", "topCompletion"), eventNames())
  }

  @Test
  fun otherFailuresAreNotRetried() = onMain {
    resize(300, 200)
    setSource(URL)
    loader.loads[0].fail(LoadErrorCode.DECODE)

    host.onHostPause()
    host.onHostResume(null)

    assertEquals(1, loader.loads.size)
  }

  // iOS reports a dropped connection only after the app is back; Android may too.
  @Test
  fun aLoadCutOffByTheBackgroundRetriesAsSoonAsItFails() = onMain {
    resize(300, 200)
    setSource(URL)
    host.onHostPause()
    host.onHostResume(null)

    loader.loads[0].fail()

    assertEquals(2, loader.loads.size)
  }

  // The app keeps running briefly after it is paused, so a source can arrive
  // then; the suspension that follows cuts its load.
  @Test
  fun aLoadStartedInTheBackgroundRetriesWhenCutOffAfterTheReturn() = onMain {
    resize(300, 200)
    host.onHostPause()
    setSource(URL)
    host.onHostResume(null)
    assertEquals("still in flight: nothing to retry", 1, loader.loads.size)

    loader.loads[0].fail()

    assertEquals(2, loader.loads.size)
  }

  @Test
  fun aFailedRetryWaitsForTheNextReturn() = onMain {
    resize(300, 200)
    setSource(URL)
    loader.loads[0].fail()
    host.onHostPause()
    host.onHostResume(null)

    loader.loads[1].fail()
    assertEquals("no retry loop", 2, loader.loads.size)

    host.onHostPause()
    host.onHostResume(null)
    assertEquals(3, loader.loads.size)
  }

  @Test
  fun aDroppedViewNeverRetries() = onMain {
    resize(300, 200)
    setSource(URL)
    loader.loads[0].fail()
    view.drop()

    host.onHostPause()
    host.onHostResume(null)

    assertEquals(1, loader.loads.size)
  }

  // MARK: Helpers

  /** A 300×200 view showing [request]'s image, with that load's events cleared. */
  private fun showLoadedImage(
    request: ImageRequest = ImageRequest(uri = URL),
    decodedWidth: Int = 300,
    decodedHeight: Int = 200,
    animated: Boolean = false,
  ) {
    resize(300, 200)
    view.request = request
    view.onTransactionEnd()
    loader.loads.single().succeed(decodedWidth, decodedHeight, animated)
    assertEquals(listOf("topStart", "topSuccess", "topCompletion"), eventNames())
    events.clear()
  }

  private fun setSource(uri: String) {
    view.request = view.request.copy(uri = uri)
    view.onTransactionEnd()
  }

  /** Gives the view a frame, as Fabric does. */
  private fun resize(width: Int, height: Int) {
    view.measure(
      View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
      View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
    view.layout(0, 0, width, height)
  }

  private fun eventNames() = events.map { it.first }

  private fun onMain(block: () -> Unit) {
    var failure: Throwable? = null
    instrumentation.runOnMainSync {
      try {
        block()
      } catch (t: Throwable) {
        failure = t
      }
    }
    failure?.let { throw it }
  }

  private companion object {
    // Never fetched: the fake loader serves every request.
    const val URL = "https://images.example.com/photos/harbour.jpg"
    const val THUMB_URL = "https://images.example.com/photos/harbour-thumb.jpg"
  }
}

/**
 * An adapter whose loads finish when a test says so. Like Coil, it sets the
 * image before reporting success and never calls back after a cancel.
 */
private class FakeLoader : ImageLoaderAdapter {
  inner class Load(
    val target: ImageView,
    val request: ResolvedRequest,
    val options: ImageLoaderAdapter.DisplayOptions,
    val listener: ImageLoaderAdapter.Listener,
  ) {
    var cancelled = false

    fun succeed(width: Int, height: Int, animated: Boolean = false) {
      check(!cancelled) { "a cancelled load cannot succeed" }
      target.setImageDrawable(SizedDrawable(width, height))
      listener.onSuccess(width, height, animated)
    }

    fun fail(code: LoadErrorCode = LoadErrorCode.NETWORK) {
      check(!cancelled) { "a cancelled load cannot fail" }
      listener.onError(code.nativeValue, "fake ${code.name.lowercase()} failure")
    }
  }

  val loads = mutableListOf<Load>()

  /** One placeholder load; [deliver] answers it as the adapter would. */
  class PlaceholderLoad(val request: ResolvedRequest, private val onDone: (Drawable?) -> Unit) {
    var cancelled = false

    /** Ignores [cancelled] so tests can play a misbehaving adapter. */
    fun deliver(drawable: Drawable?) = onDone(drawable)
  }

  val placeholderLoads = mutableListOf<PlaceholderLoad>()

  override fun loadPlaceholder(sizeOf: ImageView, request: ResolvedRequest, onDone: (Drawable?) -> Unit): LoadHandle {
    val load = PlaceholderLoad(request, onDone)
    placeholderLoads += load
    return LoadHandle { load.cancelled = true }
  }

  override fun load(
    target: ImageView,
    request: ResolvedRequest,
    options: ImageLoaderAdapter.DisplayOptions,
    listener: ImageLoaderAdapter.Listener,
  ): LoadHandle {
    val load = Load(target, request, options, listener)
    loads += load
    return LoadHandle { load.cancelled = true }
  }

  // The view never uses the cache module's half of the seam.
  override fun prefetch(request: ResolvedRequest, onDone: (Boolean) -> Unit) = error("not used")

  override fun imageSize(
    request: ResolvedRequest,
    onSize: (width: Int, height: Int) -> Unit,
    onError: (code: Int, message: String) -> Unit,
  ) = error("not used")

  override fun remove(requests: List<ResolvedRequest>, onDone: (Throwable?) -> Unit) = error("not used")

  override fun clearMemoryCache() = error("not used")

  override fun clearDiskCache(onDone: (Throwable?) -> Unit) = error("not used")

  override fun memoryCachedDrawable(cacheKey: String, resources: Resources): Drawable? = null
}

/** A stand-in for a decoded bitmap; only its size matters. */
private class SizedDrawable(private val width: Int, private val height: Int) : ColorDrawable(0xFF336699.toInt()) {
  override fun getIntrinsicWidth() = width

  override fun getIntrinsicHeight() = height
}
