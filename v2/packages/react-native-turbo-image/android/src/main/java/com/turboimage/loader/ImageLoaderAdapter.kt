package com.turboimage.loader

import android.widget.ImageView
import com.turboimage.core.ResolvedRequest

/**
 * The Android loader seam, the counterpart of `TIImageLoading` on iOS.
 *
 * The view layer only knows this interface, so Coil stays a replaceable
 * adapter (RFC rule 1) and no Coil type appears in TurboImage's API.
 *
 * Contract:
 *  * [load] is called on the main thread.
 *  * Exactly one [Listener] callback fires, on the main thread, unless the
 *    handle is cancelled first, in which case none fire.
 *  * [LoadHandle.cancel] is idempotent and safe after completion.
 */
interface ImageLoaderAdapter {
  fun load(target: ImageView, request: ResolvedRequest, listener: Listener): LoadHandle

  interface Listener {
    fun onSuccess(width: Int, height: Int)

    /**
     * @param code a `turboimage::LoadErrorCode` value; adapters classify
     *   their loader's errors so JS sees the same code on both platforms.
     * @param message diagnostic text only; not part of the contract.
     */
    fun onError(code: Int, message: String)
  }
}

fun interface LoadHandle {
  fun cancel()
}
