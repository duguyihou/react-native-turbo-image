package com.turboimage

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import androidx.annotation.VisibleForTesting

/**
 * Tells views, on the main thread, that the device regained a network after
 * losing it, so a view that failed offline in the foreground retries without
 * waiting for a trip to the background (as iOS's path monitor does).
 *
 * Needs `ACCESS_NETWORK_STATE`, which the library's manifest declares. It is
 * still checked before registering: an app may strip it
 * (`tools:node="remove"`), and registering without it throws. Such an app
 * retries on the return to the foreground only.
 */
internal object NetworkReturns {
  // Main thread only.
  private val listeners = mutableSetOf<() -> Unit>()
  private var registered = false

  fun add(context: Context, listener: () -> Unit) {
    listeners += listener
    register(context.applicationContext)
  }

  fun remove(listener: () -> Unit) {
    listeners -= listener
  }

  /** How many views listen; the view tests check a drop unregisters. */
  @get:VisibleForTesting
  val listenerCount: Int
    get() = listeners.size

  /** What the callback runs; the view tests call it directly. */
  @VisibleForTesting
  fun networkReturned() {
    // A copy: a listener may remove itself.
    listeners.toList().forEach { it() }
  }

  // One callback for the process, kept for its life (one registration).
  private fun register(context: Context) {
    if (registered) return
    registered = true
    if (context.checkSelfPermission(Manifest.permission.ACCESS_NETWORK_STATE) != PackageManager.PERMISSION_GRANTED) {
      return
    }
    val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return
    val main = Handler(Looper.getMainLooper())
    connectivity.registerDefaultNetworkCallback(
      object : ConnectivityManager.NetworkCallback() {
        // On the callback's own thread. Registration reports the current
        // network as available; only one that follows a loss is a return.
        // A switch between networks can report the new one before losing
        // the old, which is no return either: nothing was offline.
        @Volatile private var lost = false

        override fun onLost(network: Network) {
          lost = true
        }

        override fun onAvailable(network: Network) {
          if (lost) {
            lost = false
            main.post { networkReturned() }
          }
        }
      })
  }
}
