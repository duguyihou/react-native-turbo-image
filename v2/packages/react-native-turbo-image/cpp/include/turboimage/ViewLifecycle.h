// TurboImage core: the load lifecycle of one <TurboImage> view.
//
// What a view shows, and which events JS sees, depends on the order in
// which five things happen: props change, a load is started, the loader
// calls back, a placeholder finishes decoding on another thread, and the
// view is reused. The bugs live in the orderings (a callback from a load
// that was replaced, a placeholder that arrives after the image), and both
// native views used to answer them with the same hand-mirrored flags.
//
// This is that state machine, once (RFC rules 3 and 4). It decides; it does
// not act. Each step takes what happened and returns the effects the view
// must carry out, in order: cancel the load, clear the image, emit an event.
// The view owns everything that touches a platform type: the image on
// screen, the adapter's handle, the request, the event payloads.
//
// Ownership/threading: a plain value type holding per-view state, like
// `ProgressThrottle`. Each view owns one and uses it on the main thread
// only. Five integers, so the Android view can keep it in a LongArray and
// pass it through JNI with no native handle.
//
// Re-entrancy: an adapter may call back inside the call that starts a load
// (a memory-cache hit). So a view carrying out `StartLoad` may call
// `loadSucceeded` before it has finished with the effects of `reload`. That
// is safe because `StartLoad` is always the last effect of its list.

#pragma once

#include <cstdint>
#include <vector>

namespace turboimage {

// What the view holds for the current request. Exactly one applies at any
// time. Pinned ABI, like `CachePolicy`.
enum class Showing : std::int32_t {
  // No image of the current request: the view is blank or shows the
  // placeholder. Before the first load, and while a load runs.
  NoImage = 0,
  // The image of the previous request, kept while the current load runs
  // (see `reload`). It stands in for the placeholder, so no placeholder may
  // replace it.
  PreviousImage = 1,
  // The current request's image. A late placeholder must not replace it.
  LoadedImage = 2,
  // The current load failed. Without `showPlaceholderOnFailure` no
  // placeholder may appear any more, even one whose decode finishes later.
  Failed = 3,
};

// Which placeholder the props ask for. JS allows one kind at a time.
// Pinned ABI.
enum class PlaceholderKind : std::int32_t {
  None = 0,
  // A blurhash or thumbhash: decoded off the main thread.
  Hash = 1,
  // `placeholder.memoryCacheKey`: a synchronous memory-cache lookup.
  MemoryCacheKey = 2,
};

// The props the lifecycle depends on, as of the step being taken. Passed
// with each step instead of stored: the views already hold them, and a
// second copy could go stale.
struct LifecycleProps {
  PlaceholderKind placeholder = PlaceholderKind::None;
  // 1.x semantics: false removes the placeholder when the load fails.
  bool showPlaceholderOnFailure = false;
};

// One thing the view must do. Pinned ABI.
struct LifecycleEffect {
  enum class Kind : std::int32_t {
    // Cancel the adapter's load and forget its handle.
    CancelLoad = 0,
    // Remove whatever is on screen (image or placeholder).
    ClearImage = 1,
    // Emit onCompletion {state: 'cancelled'}: a load was superseded.
    EmitCancelled = 2,
    // Emit onCompletion {state: 'completed'}.
    EmitCompleted = 3,
    // Emit onFailure for a request that could not be started (the core
    // rejected it, or no adapter is linked). No onStart precedes it.
    DeliverInvalidRequest = 4,
    // Emit onStart, then hand the request to the adapter. `value` is the
    // load's token: the view passes it back with the adapter's callbacks.
    // Always the last effect of its list (see "Re-entrancy" above).
    StartLoad = 5,
    // The load in flight succeeded: show its image if the adapter has not
    // already (iOS shows it; Coil paints the ImageView itself), finish
    // progress, emit onSuccess.
    DeliverSuccess = 6,
    // The load in flight failed: emit onFailure with the adapter's error.
    DeliverFailure = 7,
    // Look `placeholder.memoryCacheKey` up in the memory cache and show the
    // hit, or nothing on a miss.
    ShowCachedPlaceholder = 8,
    // Decode the hash off the main thread, then ask `placeholderDecoded`
    // with `value` (the decode's generation) before showing the result.
    DecodePlaceholder = 9,
  };

  Kind kind;
  std::int64_t value = 0;

  friend bool operator==(const LifecycleEffect&, const LifecycleEffect&) = default;
};

using LifecycleEffects = std::vector<LifecycleEffect>;

struct ViewLifecycle {
  // A `Showing` value; int64 for the JNI LongArray, like the rest.
  std::int64_t showing = 0;
  // The token of the load in flight, 0 when there is none: made before the
  // adapter is called, 0 again once the load succeeds, fails or is
  // cancelled. A callback acts only while its own token is still here.
  //
  // A token and not the adapter's handle: a memory-cache hit calls back
  // inside the call that starts the load, before that handle exists.
  std::int64_t inFlight = 0;
  // The last token handed out; tokens are never reused within a view.
  std::int64_t lastToken = 0;
  // Bumped whenever a placeholder decode is started or invalidated, so an
  // older decode finishing late is dropped.
  std::int64_t placeholderGeneration = 0;
  // The token of an upgrade in flight, 0 when there is none (see
  // `startUpgrade`). Never at the same time as `inFlight`.
  std::int64_t upgrading = 0;

  [[nodiscard]] Showing showingState() const { return static_cast<Showing>(showing); }

  // A request prop changed: end the load in flight, decide what stays on
  // screen, and start the new load.
  //
  // What stays while the new load runs (expo-image's rule):
  //   * `recyclingKey` unchanged: the previous image, so a changed source or
  //     processor swaps without a blank frame in between;
  //   * `recyclingKey` changed: nothing, or the placeholder. The view is
  //     being reused for other content, and the old image would be wrong.
  // Only a loaded image is kept, never a placeholder or a failed view;
  // `imageOnScreen` says whether the view actually has one to keep.
  //
  // `requestValid` is false when the request cannot be started. It then
  // fails at once, with no onStart, because no load began.
  //
  // The view calls `applyPlaceholder` after carrying these effects out: a
  // reload may have cleared the view. (After, not as part of this list: a
  // load that completed inside `StartLoad` changes the answer.)
  [[nodiscard]] LifecycleEffects reload(bool recyclingKeyChanged, bool imageOnScreen,
                                        bool requestValid, const LifecycleProps& props);

  // True while `token` is the load in flight. For callbacks that need the
  // guard but no decision: progress, and whether to keep the handle the
  // adapter returned (not if the load already finished inside that call).
  [[nodiscard]] bool isInFlight(std::int64_t token) const { return token != 0 && inFlight == token; }

  // The adapter's callbacks. Empty for a token that is no longer in flight:
  // a replaced load calling back late must not touch the view.
  [[nodiscard]] LifecycleEffects loadSucceeded(std::int64_t token);
  [[nodiscard]] LifecycleEffects loadFailed(std::int64_t token, const LifecycleProps& props);

  // Upgrades: the view has grown past its image (`needsLargerDecode`) and
  // loads the same request again at its new size. Silent by design: JS hears
  // nothing, because the props did not change and the image it was told
  // about is still the one on screen, only sharper. So there is no onStart,
  // no progress, no onSuccess, and a failed upgrade leaves the image as it
  // is.
  //
  // Only over a loaded image with nothing in flight: a load in flight will
  // be decoded for the view's size anyway, and a placeholder or a failure is
  // not the image to sharpen. One upgrade at a time; the view asks again
  // when one succeeds, in case the view kept growing meanwhile.
  //
  // Returns the upgrade's token, or 0 if none may start. The view starts
  // the load itself (no effect list: there is nothing else to do), and
  // passes the token back with the adapter's callbacks. A reload, recycle or
  // drop cancels a running upgrade with `CancelLoad` and no event.
  [[nodiscard]] std::int64_t startUpgrade();

  // True while `token` is the upgrade in flight: whether to keep the handle
  // the adapter returned (a memory hit may finish inside that call).
  [[nodiscard]] bool isUpgrading(std::int64_t token) const {
    return token != 0 && upgrading == token;
  }

  // The adapter's callbacks for an upgrade. `upgradeSucceeded` is true if
  // the view must show the new image (iOS; Coil paints it on Android);
  // false for an upgrade that is no longer current, which shows nothing.
  [[nodiscard]] bool upgradeSucceeded(std::int64_t token);
  void upgradeFailed(std::int64_t token);

  // (Re)applies the placeholder the props name: after a reload, and when a
  // placeholder prop changes. Does nothing while an image holds the view
  // (`placeholderAllowed`). With no placeholder asked for, whatever the view
  // shows is one the props have since dropped, so it is cleared.
  [[nodiscard]] LifecycleEffects applyPlaceholder(const LifecycleProps& props);

  // A decode started by `DecodePlaceholder` has finished. True if its
  // result may be shown: it is still the newest decode, and no image (or
  // failure) has taken the view since.
  [[nodiscard]] bool placeholderDecoded(std::int64_t generation, const LifecycleProps& props) const;

  // iOS `prepareForRecycle`: the view goes back to Fabric's pool and will
  // be mounted for another component. Everything is reset, and JS hears
  // nothing: the component that started the load is gone.
  [[nodiscard]] LifecycleEffects recycle();

  // Android `onDropViewInstance`: the view is gone for good. Stops the load
  // and any decode; nothing is cleared on a view nobody will see again.
  [[nodiscard]] LifecycleEffects drop();

 private:
  [[nodiscard]] bool placeholderAllowed(const LifecycleProps& props) const;
  void fail(const LifecycleProps& props, LifecycleEffects& effects);
};

}  // namespace turboimage
