package com.turboimage.core

/**
 * The load lifecycle of one view; every decision is the C++ core's
 * (`turboimage::ViewLifecycle`, shared with the iOS view). Each step says
 * what happened and returns the [Effect]s the view must carry out, in
 * order. Holds only state, owned by one view and used on the main thread.
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
    /**
     * Mirrors `turboimage::LifecycleEffect::Kind`, in the same order:
     * effects are decoded by position. `TurboImageJni.cpp` asserts it.
     */
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

  // Mirrors ViewLifecycle's fields: showing, inFlight, lastToken,
  // placeholderGeneration. All start at 0, as in C++.
  private val state = LongArray(4)

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

  fun loadFailed(token: Long, placeholder: PlaceholderKind, showPlaceholderOnFailure: Boolean): List<Effect> =
    effects(TurboImageCore.nativeLifecycleLoadFailed(state, token, placeholder.nativeValue, showPlaceholderOnFailure))

  fun applyPlaceholder(placeholder: PlaceholderKind, showPlaceholderOnFailure: Boolean): List<Effect> =
    effects(TurboImageCore.nativeLifecycleApplyPlaceholder(state, placeholder.nativeValue, showPlaceholderOnFailure))

  fun placeholderDecoded(generation: Long, placeholder: PlaceholderKind, showPlaceholderOnFailure: Boolean): Boolean =
    TurboImageCore.nativeLifecyclePlaceholderDecoded(state, generation, placeholder.nativeValue, showPlaceholderOnFailure)

  fun drop(): List<Effect> = effects(TurboImageCore.nativeLifecycleDrop(state))

  // (kind, value) pairs, as the JNI bridge returns them.
  private fun effects(flat: LongArray): List<Effect> =
    List(flat.size / 2) { i -> Effect(Effect.Kind.entries[flat[2 * i].toInt()], flat[2 * i + 1]) }
}
