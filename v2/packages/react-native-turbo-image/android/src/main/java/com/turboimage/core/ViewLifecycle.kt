package com.turboimage.core

/**
 * One view's load lifecycle, decided by the C++ core (shared with iOS). Each
 * step returns the [Effect]s to run in order. Main thread only.
 */
class ViewLifecycle {
  /** Mirrors `turboimage::PlaceholderKind`; the ints are a pinned ABI. */
  enum class PlaceholderKind(val nativeValue: Int) {
    NONE(0),
    HASH(1),
    MEMORY_CACHE_KEY(2),
  }

  /** One thing the view must do; see `turboimage::LifecycleEffect`. */
  data class Effect(val kind: Kind, val value: Long) {
    /** Same order as `turboimage::LifecycleEffect::Kind` (decoded by position). */
    enum class Kind {
      CANCEL_LOAD,
      CLEAR_IMAGE,
      EMIT_CANCELLED,
      EMIT_COMPLETED,
      DELIVER_INVALID_REQUEST,
      START_LOAD,
      DELIVER_SUCCESS,
      DELIVER_FAILURE,
      SHOW_CACHED_PLACEHOLDER,
      DECODE_PLACEHOLDER,
    }
  }

  // showing, inFlight, lastToken, placeholderGeneration, upgrading, retryable.
  private val state = LongArray(6)

  fun reload(
    recyclingKeyChanged: Boolean,
    imageOnScreen: Boolean,
    requestValid: Boolean,
    placeholder: PlaceholderKind,
    showPlaceholderOnFailure: Boolean,
  ): List<Effect> =
    effects(
      TurboImageCore.nativeLifecycleReload(
        state, recyclingKeyChanged, imageOnScreen, requestValid, placeholder.nativeValue, showPlaceholderOnFailure))

  fun isInFlight(token: Long): Boolean = TurboImageCore.nativeLifecycleIsInFlight(state, token)

  fun loadSucceeded(token: Long): List<Effect> = effects(TurboImageCore.nativeLifecycleLoadSucceeded(state, token))

  /** [code] is a [LoadErrorCode] value; only `NETWORK` failures may be retried. */
  fun loadFailed(
    token: Long,
    placeholder: PlaceholderKind,
    showPlaceholderOnFailure: Boolean,
    code: Int,
  ): List<Effect> =
    effects(
      TurboImageCore.nativeLifecycleLoadFailed(
        state, token, placeholder.nativeValue, showPlaceholderOnFailure, code))

  /** Whether [retry] would start a load; a plain read, for the many views that won't. */
  fun mayRetry(): Boolean = state[5] != 0L

  /** The failed load again, as a new load with events; empty if it may not retry. */
  fun retry(placeholder: PlaceholderKind, showPlaceholderOnFailure: Boolean): List<Effect> =
    effects(TurboImageCore.nativeLifecycleRetry(state, placeholder.nativeValue, showPlaceholderOnFailure))

  fun applyPlaceholder(placeholder: PlaceholderKind, showPlaceholderOnFailure: Boolean): List<Effect> =
    effects(TurboImageCore.nativeLifecycleApplyPlaceholder(state, placeholder.nativeValue, showPlaceholderOnFailure))

  fun placeholderDecoded(generation: Long, placeholder: PlaceholderKind, showPlaceholderOnFailure: Boolean): Boolean =
    TurboImageCore.nativeLifecyclePlaceholderDecoded(state, generation, placeholder.nativeValue, showPlaceholderOnFailure)

  fun drop(): List<Effect> = effects(TurboImageCore.nativeLifecycleDrop(state))

  /** Token for a silent reload at the larger size, or 0 if none may start. */
  fun startUpgrade(): Long = TurboImageCore.nativeLifecycleStartUpgrade(state)

  fun isUpgrading(token: Long): Boolean = TurboImageCore.nativeLifecycleIsUpgrading(state, token)

  /** True if the upgrade is still current (Coil has already painted it). */
  fun upgradeSucceeded(token: Long): Boolean = TurboImageCore.nativeLifecycleUpgradeSucceeded(state, token)

  fun upgradeFailed(token: Long) = TurboImageCore.nativeLifecycleUpgradeFailed(state, token)

  companion object {
    /** `turboimage::needsLargerDecode`: sizes in pixels. */
    fun needsLargerDecode(
      decodedWidth: Int,
      decodedHeight: Int,
      loadedForWidth: Int,
      loadedForHeight: Int,
      nowWidth: Int,
      nowHeight: Int,
      fill: Boolean,
    ): Boolean =
      TurboImageCore.nativeNeedsLargerDecode(
        decodedWidth.toDouble(), decodedHeight.toDouble(),
        loadedForWidth.toDouble(), loadedForHeight.toDouble(),
        nowWidth.toDouble(), nowHeight.toDouble(), fill)
  }

  // (kind, value) pairs, as the JNI bridge returns them.
  private fun effects(flat: LongArray): List<Effect> =
    List(flat.size / 2) { i -> Effect(Effect.Kind.entries[flat[2 * i].toInt()], flat[2 * i + 1]) }
}
