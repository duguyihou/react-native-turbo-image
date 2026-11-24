package com.turboimage.loader

import android.app.Activity
import android.graphics.drawable.Drawable
import android.os.Bundle
import android.widget.FrameLayout
import android.widget.ImageView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.turboimage.core.CachePolicy
import com.turboimage.core.ImageRequest
import com.turboimage.core.LoadErrorCode
import com.turboimage.core.Processing
import com.turboimage.core.ResizeMode
import com.turboimage.core.ResolvedRequest
import com.turboimage.core.TurboImageCore
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before

// Shared setup for the loader tests: the real Coil adapter driven through the
// seam, the real core, a real window, and images from scripts/fixture-server.py.
// A server (not files) because local files skip the cache tiers, and its
// request counts tell a cache hit from a fetch. Run via
// scripts/test-android-adapter.sh.

/** An empty window for the image views under test. */
class TestActivity : Activity() {
  lateinit var root: FrameLayout
    private set

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    root = FrameLayout(this)
    setContentView(root)
  }
}

/** What the seam's listener was told about one load. */
data class Outcome(
  val view: ImageView,
  /** The decoded size, or null if the load failed or never completed. */
  val width: Int? = null,
  val height: Int? = null,
  /** A `LoadErrorCode`, or null if the load succeeded or never completed. */
  val error: LoadErrorCode? = null,
  val message: String? = null,
  /** Every progress callback, in order, as (received, expected). */
  val progress: List<Pair<Long, Long>> = emptyList(),
  /** Whether any progress callback arrived after the load had completed. */
  val progressAfterCompletion: Boolean = false,
  /** False for a load that was cancelled, or timed out. */
  val completed: Boolean = false,
) {
  val succeeded: Boolean
    get() = completed && error == null
}

/** One process-wide adapter, like an app has (`TurboImageLoaders`). */
private val sharedAdapter: CoilImageLoaderAdapter by lazy {
  CoilImageLoaderAdapter(InstrumentationRegistry.getInstrumentation().targetContext)
}

/**
 * Base test class: a window, the adapter, and helpers. Tests share the
 * adapter's caches, so [photo] and [fixture] give every URL a random name.
 */
internal abstract class AdapterTest {
  protected val adapter: CoilImageLoaderAdapter
    get() = sharedAdapter

  private lateinit var scenario: ActivityScenario<TestActivity>

  @Before
  fun openWindow() {
    assertTrue(
      "The fixture server is not reachable at $BASE. Run scripts/test-android-adapter.sh, " +
        "which starts it and runs `adb reverse`.",
      fixtureServerAnswers(),
    )
    scenario = ActivityScenario.launch(TestActivity::class.java)
  }

  @After
  fun closeWindow() {
    scenario.close()
  }

  // MARK: Requests

  /** A 600×400 JPEG under a URL of its own. */
  protected fun photo(route: String = "photo") = "$BASE/$route/${UUID.randomUUID()}.jpg"

  /** One of the server's fixed fixtures, under a cache key of its own. */
  protected fun fixture(path: String) = "$BASE/$path?test=${UUID.randomUUID()}"

  /** [uri] as the core resolves it for a view; fails if the core rejects it. */
  protected fun resolve(
    uri: String,
    cachePolicy: CachePolicy = CachePolicy.DEFAULT,
    processing: Processing = Processing(),
    allowDownscaling: Boolean = true,
    resizeMode: ResizeMode = ResizeMode.CONTAIN,
    headers: List<Pair<String, String>> = emptyList(),
  ): ResolvedRequest {
    val request =
      ImageRequest(
        uri = uri,
        headers = headers,
        cachePolicy = cachePolicy,
        processing = processing,
        allowDownscaling = allowDownscaling,
        resizeMode = resizeMode,
      )
    val resolved = TurboImageCore.resolve(request, pixelRatio = 1.0)
    return resolved as? ResolvedRequest ?: throw AssertionError("The core rejected $uri: $resolved")
  }

  // MARK: Loading

  /** Loads [request] into a new [width]×[height] view and waits for it. */
  protected fun load(
    request: ResolvedRequest,
    width: Int = VIEW_WIDTH,
    height: Int = VIEW_HEIGHT,
    options: ImageLoaderAdapter.DisplayOptions = NO_FADE,
  ): Outcome = loadInto(addView(width, height), request, options)

  /** Loads [request] into [view], which may already show something. */
  protected fun loadInto(
    view: ImageView,
    request: ResolvedRequest,
    options: ImageLoaderAdapter.DisplayOptions = NO_FADE,
  ): Outcome {
    val pending = start(view, request, options)
    assertTrue("The load of ${request.url} did not complete", pending.await())
    return pending.outcome()
  }

  /** A load in flight: what [start] returns, for tests that cancel. */
  protected inner class Pending(val view: ImageView) : ImageLoaderAdapter.Listener {
    lateinit var handle: LoadHandle
    private val done = CountDownLatch(1)
    // Only touched on the main thread.
    private var result = Outcome(view)

    override fun onProgress(completed: Long, total: Long) {
      result =
        if (result.completed) result.copy(progressAfterCompletion = true)
        else result.copy(progress = result.progress + (completed to total))
    }

    override fun onSuccess(width: Int, height: Int) {
      result = result.copy(width = width, height = height, completed = true)
      done.countDown()
    }

    override fun onError(code: Int, message: String) {
      result =
        result.copy(
          error = LoadErrorCode.entries.first { it.nativeValue == code },
          message = message,
          completed = true,
        )
      done.countDown()
    }

    fun await(seconds: Long = TIMEOUT_SECONDS): Boolean = done.await(seconds, TimeUnit.SECONDS)

    fun outcome(): Outcome = onMain { result }
  }

  /** Starts a load without waiting for it. */
  protected fun start(
    view: ImageView,
    request: ResolvedRequest,
    options: ImageLoaderAdapter.DisplayOptions = NO_FADE,
  ): Pending {
    val pending = Pending(view)
    onMain { pending.handle = adapter.load(view, request, options, pending) }
    return pending
  }

  /** A new image view in the window, laid out at exactly this size. */
  protected fun addView(width: Int = VIEW_WIDTH, height: Int = VIEW_HEIGHT): ImageView {
    lateinit var view: ImageView
    scenario.onActivity { activity ->
      view = ImageView(activity)
      activity.root.addView(view, FrameLayout.LayoutParams(width, height))
    }
    // Lay out before loading, as Fabric does.
    InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    return view
  }

  protected fun prefetch(request: ResolvedRequest): Boolean {
    val done = CountDownLatch(1)
    var succeeded = false
    onMain {
      adapter.prefetch(request) {
        succeeded = it
        done.countDown()
      }
    }
    assertTrue("The prefetch of ${request.url} did not complete", done.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))
    return succeeded
  }

  // MARK: Caches

  /** `TurboImage.dispose`: waits for the disk work, fails on its error. */
  protected fun remove(vararg requests: ResolvedRequest) = awaitDiskWork { adapter.remove(requests.toList(), it) }

  protected fun clearDiskCache() = awaitDiskWork { adapter.clearDiskCache(it) }

  protected fun clearMemoryCache() = onMain { adapter.clearMemoryCache() }

  /** The `memoryCacheKey` placeholder lookup. */
  protected fun memoryCached(request: ResolvedRequest): Drawable? = onMain {
    adapter.memoryCachedDrawable(request.cacheKey, InstrumentationRegistry.getInstrumentation().targetContext.resources)
  }

  /** Whether [uri] loads under `cacheOnly` (either tier, no network). */
  protected fun isCached(uri: String): Boolean = load(resolve(uri, CachePolicy.CACHE_ONLY)).succeeded

  private fun awaitDiskWork(work: ((Throwable?) -> Unit) -> Unit) {
    val done = CountDownLatch(1)
    var failure: Throwable? = null
    onMain {
      work {
        failure = it
        done.countDown()
      }
    }
    assertTrue("The disk-cache work did not finish", done.await(TIMEOUT_SECONDS, TimeUnit.SECONDS))
    failure?.let { throw AssertionError("The disk-cache work failed", it) }
  }

  // MARK: The fixture server

  /** How many requests for [uri]'s path the server has received. */
  protected fun requestsReceived(uri: String): Int = hits(uri).getInt("count")

  /** Of those, how many were conditional (`If-None-Match`). */
  protected fun conditionalRequestsReceived(uri: String): Int = hits(uri).getInt("conditional")

  private fun hits(uri: String): JSONObject = JSONObject(httpGet("$BASE/__hits?path=${URL(uri).path}")!!)

  private fun fixtureServerAnswers(): Boolean = httpGet("$BASE/__ping") == "ok"

  /** The body of a GET, or null if the server cannot be reached. */
  private fun httpGet(url: String): String? =
    try {
      val connection = URL(url).openConnection() as HttpURLConnection
      connection.connectTimeout = 3000
      connection.readTimeout = 3000
      connection.inputStream.use { it.readBytes().decodeToString() }
    } catch (e: java.io.IOException) {
      null
    }

  // MARK: Threads

  /** Runs [block] on the main thread, where the seam must be called. */
  protected fun <T> onMain(block: () -> T): T {
    var result: Result<T>? = null
    InstrumentationRegistry.getInstrumentation().runOnMainSync { result = runCatching(block) }
    return result!!.getOrThrow()
  }

  /** Lets the main thread run for a while, for things that must *not* happen. */
  protected fun settle(millis: Long) {
    Thread.sleep(millis)
    InstrumentationRegistry.getInstrumentation().waitForIdleSync()
  }

  protected companion object {
    /** Must match `fixture_server_port` in scripts/fixture-server.sh. */
    const val BASE = "http://localhost:8765"

    /** The fixture photo's size, and the default view's: half of it. */
    const val PHOTO_WIDTH = 600
    const val PHOTO_HEIGHT = 400
    const val VIEW_WIDTH = 300
    const val VIEW_HEIGHT = 200

    const val TIMEOUT_SECONDS = 20L

    /** No cross-fade, so `view.drawable` is the loaded image, not a `CrossfadeDrawable`. */
    val NO_FADE = ImageLoaderAdapter.DisplayOptions(fadeMillis = 0)
  }
}
