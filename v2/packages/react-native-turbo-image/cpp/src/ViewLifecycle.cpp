#include "turboimage/ViewLifecycle.h"

namespace turboimage {

namespace {

using Kind = LifecycleEffect::Kind;

std::int64_t toField(Showing showing) {
  return static_cast<std::int64_t>(showing);
}

}  // namespace

bool ViewLifecycle::placeholderAllowed(const LifecycleProps& props) const {
  switch (showingState()) {
    case Showing::NoImage:
      return true;
    case Showing::PreviousImage:
    case Showing::LoadedImage:
      return false;
    case Showing::Failed:
      return props.showPlaceholderOnFailure;
  }
  return false;
}

LifecycleEffects ViewLifecycle::applyPlaceholder(const LifecycleProps& props) {
  // Always invalidate decodes started for earlier props.
  const std::int64_t generation = ++placeholderGeneration;
  if (!placeholderAllowed(props)) {
    // Over a failure, only `showPlaceholderOnFailure` let a placeholder
    // show; with it now off, drop the one it kept.
    if (showingState() == Showing::Failed) {
      return {{.kind = Kind::ClearImage}};
    }
    return {};
  }
  switch (props.placeholder) {
    case PlaceholderKind::MemoryCacheKey:
      // A miss clears the view, as for `None` below.
      return {{.kind = Kind::ShowCachedPlaceholder}};
    case PlaceholderKind::Hash:
      return {{.kind = Kind::DecodePlaceholder, .value = generation}};
    case PlaceholderKind::None:
      break;
  }
  // No placeholder wanted: anything shown is a dropped placeholder, so clear it.
  return {{.kind = Kind::ClearImage}};
}

bool ViewLifecycle::placeholderDecoded(std::int64_t generation, const LifecycleProps& props) const {
  return generation == placeholderGeneration && placeholderAllowed(props);
}

// Screen effects of a failed load or an unstartable request.
void ViewLifecycle::fail(const LifecycleProps& props, LifecycleEffects& effects) {
  // A kept previous image always goes; leaving it would hide the failure.
  const bool hadPreviousImage = showingState() == Showing::PreviousImage;
  showing = toField(Showing::Failed);
  if (!props.showPlaceholderOnFailure) {
    ++placeholderGeneration;  // a decode still in flight must not appear
    effects.push_back({.kind = Kind::ClearImage});
  } else if (hadPreviousImage) {
    // Show the placeholder held back by the previous image.
    effects.push_back({.kind = Kind::ClearImage});
    const auto placeholder = applyPlaceholder(props);
    effects.insert(effects.end(), placeholder.begin(), placeholder.end());
  }
}

LifecycleEffects ViewLifecycle::reload(bool recyclingKeyChanged, bool imageOnScreen,
                                       bool requestValid, const LifecycleProps& props) {
  LifecycleEffects effects;
  // A new request: the old failure is moot, and an invalid one never heals.
  retryable = 0;
  // Cancel any upgrade silently; JS never heard of it.
  if (upgrading != 0) {
    upgrading = 0;
    effects.push_back({.kind = Kind::CancelLoad});
  }
  // A superseded load emits cancelled, so every onStart gets one onCompletion.
  if (inFlight != 0) {
    inFlight = 0;
    effects.push_back({.kind = Kind::CancelLoad});
    effects.push_back({.kind = Kind::EmitCancelled});
  }

  const bool holdsImage =
      showingState() == Showing::LoadedImage || showingState() == Showing::PreviousImage;
  const bool keepsPreviousImage = holdsImage && !recyclingKeyChanged && imageOnScreen;
  showing = toField(keepsPreviousImage ? Showing::PreviousImage : Showing::NoImage);
  if (!keepsPreviousImage) {
    effects.push_back({.kind = Kind::ClearImage});
  }

  if (!requestValid) {
    effects.push_back({.kind = Kind::DeliverInvalidRequest});
    fail(props, effects);
    effects.push_back({.kind = Kind::EmitCompleted});
    return effects;
  }

  inFlight = ++lastToken;
  effects.push_back({.kind = Kind::StartLoad, .value = inFlight});
  return effects;
}

LifecycleEffects ViewLifecycle::loadSucceeded(std::int64_t token) {
  if (!isInFlight(token)) {
    return {};
  }
  inFlight = 0;
  showing = toField(Showing::LoadedImage);
  return {{.kind = Kind::DeliverSuccess}, {.kind = Kind::EmitCompleted}};
}

LifecycleEffects ViewLifecycle::loadFailed(std::int64_t token, const LifecycleProps& props,
                                           LoadErrorCode code, bool remoteSource) {
  if (!isInFlight(token)) {
    return {};
  }
  inFlight = 0;
  // Only the network can recover by itself. `NotCached` (`cacheOnly`),
  // `Decode` and `Http` (the server's answer) would fail the same way;
  // `Unknown` might loop. A local source has no network: both adapters
  // report a missing or unreadable file as an I/O failure, which reads as
  // `Network` but comes back the same after any trip to the background.
  retryable = code == LoadErrorCode::Network && remoteSource ? 1 : 0;
  LifecycleEffects effects{{.kind = Kind::DeliverFailure}};
  fail(props, effects);
  effects.push_back({.kind = Kind::EmitCompleted});
  return effects;
}

LifecycleEffects ViewLifecycle::retry(const LifecycleProps& props) {
  // `inFlight` and `upgrading` are 0 whenever the view shows a failure; the
  // checks keep a misuse from starting a second load.
  if (retryable == 0 || showingState() != Showing::Failed || inFlight != 0 || upgrading != 0) {
    return {};
  }
  retryable = 0;
  // Loading again, as after a reload of a view with no image: the view is
  // blank or shows the kept placeholder, so nothing needs clearing.
  showing = toField(Showing::NoImage);
  LifecycleEffects effects;
  if (!props.showPlaceholderOnFailure) {
    // The failure removed the placeholder; bring it back while retrying.
    effects = applyPlaceholder(props);
  }
  inFlight = ++lastToken;
  effects.push_back({.kind = Kind::StartLoad, .value = inFlight});
  return effects;
}

std::int64_t ViewLifecycle::startUpgrade() {
  if (showingState() != Showing::LoadedImage || inFlight != 0 || upgrading != 0) {
    return 0;
  }
  upgrading = ++lastToken;
  return upgrading;
}

bool ViewLifecycle::upgradeSucceeded(std::int64_t token) {
  if (!isUpgrading(token)) {
    return false;
  }
  upgrading = 0;
  return true;
}

void ViewLifecycle::upgradeFailed(std::int64_t token) {
  if (isUpgrading(token)) {
    upgrading = 0;
  }
}

LifecycleEffects ViewLifecycle::recycle() {
  LifecycleEffects effects;
  if (inFlight != 0 || upgrading != 0) {
    inFlight = 0;
    upgrading = 0;
    effects.push_back({.kind = Kind::CancelLoad});
  }
  effects.push_back({.kind = Kind::ClearImage});
  showing = toField(Showing::NoImage);
  retryable = 0;
  ++placeholderGeneration;  // drop any decode still in flight
  return effects;
}

LifecycleEffects ViewLifecycle::drop() {
  LifecycleEffects effects;
  if (inFlight != 0 || upgrading != 0) {
    inFlight = 0;
    upgrading = 0;
    effects.push_back({.kind = Kind::CancelLoad});
  }
  // The view is gone; nothing may start on it again.
  retryable = 0;
  ++placeholderGeneration;  // drop any decode still in flight
  return effects;
}

}  // namespace turboimage
