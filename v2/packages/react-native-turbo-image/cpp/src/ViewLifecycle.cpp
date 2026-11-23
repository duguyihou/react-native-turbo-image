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
  // Always: whatever this decides, a decode started for earlier props must
  // not appear any more.
  const std::int64_t generation = ++placeholderGeneration;
  if (!placeholderAllowed(props)) {
    return {};
  }
  switch (props.placeholder) {
    case PlaceholderKind::MemoryCacheKey:
      // A miss clears the view, for the same reason as `None` below. (JS
      // allows one placeholder kind at a time, so there is no hash to fall
      // back on.)
      return {{.kind = Kind::ShowCachedPlaceholder}};
    case PlaceholderKind::Hash:
      return {{.kind = Kind::DecodePlaceholder, .value = generation}};
    case PlaceholderKind::None:
      break;
  }
  // No placeholder is asked for (any more). `placeholderAllowed` says the
  // view holds no loaded image, so whatever it shows is a placeholder the
  // props have since dropped: remove it, rather than leave it up until the
  // load ends.
  return {{.kind = Kind::ClearImage}};
}

bool ViewLifecycle::placeholderDecoded(std::int64_t generation, const LifecycleProps& props) const {
  return generation == placeholderGeneration && placeholderAllowed(props);
}

// What a failure does to the screen, for a load that failed and for a
// request that could not be started.
void ViewLifecycle::fail(const LifecycleProps& props, LifecycleEffects& effects) {
  // A previous image kept during the load goes either way: it is not what
  // the source names, and leaving it up would hide the failure.
  const bool hadPreviousImage = showingState() == Showing::PreviousImage;
  showing = toField(Showing::Failed);
  if (!props.showPlaceholderOnFailure) {
    ++placeholderGeneration;  // a decode still in flight must not appear
    effects.push_back({.kind = Kind::ClearImage});
  } else if (hadPreviousImage) {
    // The placeholder was held back while the previous image stood in.
    effects.push_back({.kind = Kind::ClearImage});
    const auto placeholder = applyPlaceholder(props);
    effects.insert(effects.end(), placeholder.begin(), placeholder.end());
  }
}

LifecycleEffects ViewLifecycle::reload(bool recyclingKeyChanged, bool imageOnScreen,
                                       bool requestValid, const LifecycleProps& props) {
  LifecycleEffects effects;
  // An upgrade of the image being replaced: stop it, and say nothing, since
  // JS never heard of it.
  if (upgrading != 0) {
    upgrading = 0;
    effects.push_back({.kind = Kind::CancelLoad});
  }
  // A load still in flight is superseded: tell JS it was cancelled, so
  // every onStart is matched by exactly one onCompletion.
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

LifecycleEffects ViewLifecycle::loadFailed(std::int64_t token, const LifecycleProps& props) {
  if (!isInFlight(token)) {
    return {};
  }
  inFlight = 0;
  LifecycleEffects effects{{.kind = Kind::DeliverFailure}};
  fail(props, effects);
  effects.push_back({.kind = Kind::EmitCompleted});
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
  ++placeholderGeneration;  // drop any decode still in flight
  return effects;
}

}  // namespace turboimage
