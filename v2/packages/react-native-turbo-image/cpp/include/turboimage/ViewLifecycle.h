// TurboImage core: the load lifecycle of one <TurboImage> view, shared by
// both platforms (RFC rules 3 and 4).
//
// It decides, it does not act: each step returns the effects the view must
// carry out, in order. The view owns all platform objects.
//
// Plain value type, main thread only. Six int64s so Android can keep it
// in a LongArray across JNI.
//
// Re-entrancy: a memory-cache hit may call back inside `StartLoad`. That is
// safe because `StartLoad` is always the last effect of its list.

#pragma once

#include <cstdint>
#include <vector>

#include "turboimage/ImageRequest.h"

namespace turboimage {

// What the view holds for the current request. Pinned ABI.
enum class Showing : std::int32_t {
  // Blank or placeholder: before the first load and while one runs.
  NoImage = 0,
  // The previous request's image, kept while the new load runs. No
  // placeholder may replace it.
  PreviousImage = 1,
  // The current request's image. No late placeholder may replace it.
  LoadedImage = 2,
  // The load failed. Without `showPlaceholderOnFailure`, no placeholder
  // may appear, even a late decode.
  Failed = 3,
};

// Which placeholder the props ask for (one at a time). Pinned ABI.
enum class PlaceholderKind : std::int32_t {
  None = 0,
  // Blurhash or thumbhash, decoded off the main thread.
  Hash = 1,
  // `placeholder.memoryCacheKey`, a synchronous memory-cache lookup.
  MemoryCacheKey = 2,
};

// Props the lifecycle needs, passed with each step rather than stored so
// they cannot go stale.
struct LifecycleProps {
  PlaceholderKind placeholder = PlaceholderKind::None;
  // false removes the placeholder when the load fails.
  bool showPlaceholderOnFailure = false;
};

// One thing the view must do. Pinned ABI.
struct LifecycleEffect {
  enum class Kind : std::int32_t {
    // Cancel the adapter's load and forget its handle.
    CancelLoad = 0,
    // Remove whatever is on screen (image or placeholder).
    ClearImage = 1,
    // Emit onCompletion {state: 'cancelled'} for a superseded load.
    EmitCancelled = 2,
    // Emit onCompletion {state: 'completed'}.
    EmitCompleted = 3,
    // Emit onFailure for a request that could not start; no onStart.
    DeliverInvalidRequest = 4,
    // Emit onStart, then start the adapter. `value` is the load's token,
    // passed back with its callbacks. Always the last effect.
    StartLoad = 5,
    // Show the image unless the adapter did (Coil does), finish progress,
    // emit onSuccess.
    DeliverSuccess = 6,
    // Emit onFailure with the adapter's error.
    DeliverFailure = 7,
    // Show the memory-cache hit for `placeholder.memoryCacheKey`, if any.
    ShowCachedPlaceholder = 8,
    // Decode the hash off main, then check `placeholderDecoded(value)`
    // before showing it.
    DecodePlaceholder = 9,
  };

  Kind kind;
  std::int64_t value = 0;

  friend bool operator==(const LifecycleEffect&, const LifecycleEffect&) = default;
};

using LifecycleEffects = std::vector<LifecycleEffect>;

struct ViewLifecycle {
  // A `Showing` value.
  std::int64_t showing = 0;
  // Token of the load in flight, or 0. Callbacks act only while their token
  // is here. A token, not the adapter handle: a cache hit calls back before
  // the handle exists.
  std::int64_t inFlight = 0;
  // Last token handed out; never reused.
  std::int64_t lastToken = 0;
  // Bumped when a placeholder decode starts or is invalidated, so late
  // decodes are dropped.
  std::int64_t placeholderGeneration = 0;
  // Token of the upgrade in flight, or 0. Never set with `inFlight`.
  std::int64_t upgrading = 0;
  // 1 while the failed load may be retried (see `retry`), else 0. Only set
  // with `showing == Failed`.
  std::int64_t retryable = 0;

  [[nodiscard]] Showing showingState() const { return static_cast<Showing>(showing); }

  // A request prop changed: end the current load and start the new one.
  // Same `recyclingKey` keeps the loaded image on screen meanwhile; a new
  // one clears it (expo-image's rule). An invalid request fails at once with
  // no onStart. Call `applyPlaceholder` after carrying these out, since a
  // load may complete inside `StartLoad`.
  [[nodiscard]] LifecycleEffects reload(bool recyclingKeyChanged, bool imageOnScreen,
                                        bool requestValid, const LifecycleProps& props);

  // True while `token` is the load in flight. Guards progress, and whether
  // to keep the adapter's handle (not if the load already finished).
  [[nodiscard]] bool isInFlight(std::int64_t token) const { return token != 0 && inFlight == token; }

  // Adapter callbacks. Empty for a stale token. A `Network` failure of a
  // remote source (`isRemoteSource` of the failed load's URI) may be retried
  // (`retry`); others would fail the same way again.
  [[nodiscard]] LifecycleEffects loadFailed(std::int64_t token, const LifecycleProps& props,
                                            LoadErrorCode code, bool remoteSource);
  [[nodiscard]] LifecycleEffects loadSucceeded(std::int64_t token);

  // Retry: the same request again after a network failure, as a new load
  // with its own events (onStart ... onCompletion), so JS sees it recover.
  // Views call it when the app returns to the foreground, and right after a
  // failure of a load that began before a trip to the background (iOS drops
  // its connections there and reports it only on return). At most once per
  // failure: a retry that fails again waits for the next call. Empty unless
  // the view shows a retryable failure with nothing in flight. Reapplies the
  // placeholder the failure removed; `StartLoad` is last, as in `reload`.
  [[nodiscard]] LifecycleEffects retry(const LifecycleProps& props);

  // Upgrade: reload the same request at the view's larger size
  // (`needsLargerDecode`). Silent: no JS events, and a failure keeps the
  // current image. Only over a loaded image with nothing in flight, one at
  // a time. Returns the token, or 0 if none may start; the view starts the
  // load itself. Reload, recycle and drop cancel it without an event.
  [[nodiscard]] std::int64_t startUpgrade();

  // True while `token` is the upgrade in flight (keep the adapter handle).
  [[nodiscard]] bool isUpgrading(std::int64_t token) const {
    return token != 0 && upgrading == token;
  }

  // Upgrade callbacks. `upgradeSucceeded` is true if the view must show the
  // new image (unless Coil already did); false for a stale upgrade.
  [[nodiscard]] bool upgradeSucceeded(std::int64_t token);
  void upgradeFailed(std::int64_t token);

  // (Re)applies the placeholder after a reload, or a change to a placeholder
  // prop or `showPlaceholderOnFailure`. No-op while an image holds the view;
  // clears a dropped placeholder, or one a failure may no longer show.
  [[nodiscard]] LifecycleEffects applyPlaceholder(const LifecycleProps& props);

  // A `DecodePlaceholder` finished. True if it is still the newest decode
  // and no image or failure has taken the view.
  [[nodiscard]] bool placeholderDecoded(std::int64_t generation, const LifecycleProps& props) const;

  // iOS `prepareForRecycle`: reset everything, emit nothing (the component
  // is gone).
  [[nodiscard]] LifecycleEffects recycle();

  // Android `onDropViewInstance`: stop the load and any decode; no clear.
  [[nodiscard]] LifecycleEffects drop();

 private:
  [[nodiscard]] bool placeholderAllowed(const LifecycleProps& props) const;
  void fail(const LifecycleProps& props, LifecycleEffects& effects);
};

}  // namespace turboimage
