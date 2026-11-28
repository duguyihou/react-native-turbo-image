#include <gtest/gtest.h>

#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "turboimage/ViewLifecycle.h"

namespace turboimage {
namespace {

using Kind = LifecycleEffect::Kind;

constexpr LifecycleProps kNoPlaceholder{};
constexpr LifecycleProps kHash{.placeholder = PlaceholderKind::Hash};
constexpr LifecycleProps kHashKeptOnFailure{.placeholder = PlaceholderKind::Hash,
                                            .showPlaceholderOnFailure = true};

constexpr auto kDecode = LoadErrorCode::Decode;
constexpr auto kNetwork = LoadErrorCode::Network;
// The failed load's source is fetched over the network (`isRemoteSource`).
constexpr bool kRemote = true;

LifecycleEffects effects(std::initializer_list<LifecycleEffect> list) {
  return list;
}

// Starts a load and lets it succeed; returns the lifecycle showing its image.
ViewLifecycle loaded() {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kNoPlaceholder);
  (void)lifecycle.loadSucceeded(lifecycle.inFlight);
  return lifecycle;
}

TEST(ViewLifecycle, FirstLoadClearsTheViewAndStarts) {
  ViewLifecycle lifecycle;
  EXPECT_EQ(lifecycle.reload(false, false, true, kNoPlaceholder),
            effects({{.kind = Kind::ClearImage}, {.kind = Kind::StartLoad, .value = 1}}));
  EXPECT_TRUE(lifecycle.isInFlight(1));
  EXPECT_EQ(lifecycle.showingState(), Showing::NoImage);
}

TEST(ViewLifecycle, SuccessDeliversThenCompletes) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kNoPlaceholder);
  EXPECT_EQ(lifecycle.loadSucceeded(1),
            effects({{.kind = Kind::DeliverSuccess}, {.kind = Kind::EmitCompleted}}));
  EXPECT_FALSE(lifecycle.isInFlight(1));
  EXPECT_EQ(lifecycle.showingState(), Showing::LoadedImage);
}

TEST(ViewLifecycle, ACallbackIsHeardOnce) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kNoPlaceholder);
  (void)lifecycle.loadSucceeded(1);
  EXPECT_TRUE(lifecycle.loadSucceeded(1).empty());
  EXPECT_TRUE(lifecycle.loadFailed(1, kNoPlaceholder, kDecode, kRemote).empty());
  EXPECT_EQ(lifecycle.showingState(), Showing::LoadedImage);
}

TEST(ViewLifecycle, ASupersededLoadIsCancelledForJsAndIgnoredAfterwards) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kNoPlaceholder);
  EXPECT_EQ(lifecycle.reload(false, false, true, kNoPlaceholder),
            effects({{.kind = Kind::CancelLoad},
                     {.kind = Kind::EmitCancelled},
                     {.kind = Kind::ClearImage},
                     {.kind = Kind::StartLoad, .value = 2}}));
  // A late callback from the cancelled load must not touch the view.
  EXPECT_TRUE(lifecycle.loadSucceeded(1).empty());
  EXPECT_TRUE(lifecycle.loadFailed(1, kNoPlaceholder, kDecode, kRemote).empty());
  EXPECT_TRUE(lifecycle.isInFlight(2));
  EXPECT_EQ(lifecycle.showingState(), Showing::NoImage);
}

TEST(ViewLifecycle, TokenZeroIsNeverInFlight) {
  const ViewLifecycle idle;
  EXPECT_FALSE(idle.isInFlight(0));
}

TEST(ViewLifecycle, KeepsThePreviousImageWhileTheSameContentReloads) {
  auto lifecycle = loaded();
  // No ClearImage: the loaded image stays up during the new load.
  EXPECT_EQ(lifecycle.reload(false, true, true, kHash),
            effects({{.kind = Kind::StartLoad, .value = 2}}));
  EXPECT_EQ(lifecycle.showingState(), Showing::PreviousImage);
  // It stands in for the placeholder: none is decoded over it.
  EXPECT_TRUE(lifecycle.applyPlaceholder(kHash).empty());
  // And it is kept again if that load is superseded in turn.
  (void)lifecycle.reload(false, true, true, kHash);
  EXPECT_EQ(lifecycle.showingState(), Showing::PreviousImage);
}

TEST(ViewLifecycle, ANewRecyclingKeyDropsThePreviousImage) {
  auto lifecycle = loaded();
  EXPECT_EQ(lifecycle.reload(true, true, true, kHash),
            effects({{.kind = Kind::ClearImage}, {.kind = Kind::StartLoad, .value = 2}}));
  EXPECT_EQ(lifecycle.showingState(), Showing::NoImage);
}

TEST(ViewLifecycle, NothingIsKeptWhenTheViewHasNoImage) {
  auto lifecycle = loaded();
  (void)lifecycle.reload(false, false, true, kHash);
  EXPECT_EQ(lifecycle.showingState(), Showing::NoImage);
}

TEST(ViewLifecycle, AFailedViewOrAPlaceholderIsNeverKept) {
  ViewLifecycle failed;
  (void)failed.reload(false, false, true, kHashKeptOnFailure);
  (void)failed.loadFailed(1, kHashKeptOnFailure, kDecode, kRemote);
  // `imageOnScreen` is true: the placeholder kept on failure is up.
  (void)failed.reload(false, true, true, kHashKeptOnFailure);
  EXPECT_EQ(failed.showingState(), Showing::NoImage);
}

TEST(ViewLifecycle, AnInvalidRequestFailsWithoutAStart) {
  ViewLifecycle lifecycle;
  EXPECT_EQ(lifecycle.reload(false, false, false, kNoPlaceholder),
            effects({{.kind = Kind::ClearImage},
                     {.kind = Kind::DeliverInvalidRequest},
                     {.kind = Kind::ClearImage},
                     {.kind = Kind::EmitCompleted}}));
  EXPECT_EQ(lifecycle.inFlight, 0);
  EXPECT_EQ(lifecycle.showingState(), Showing::Failed);
}

TEST(ViewLifecycle, FailureRemovesThePlaceholderByDefault) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kHash);
  const auto decode = lifecycle.applyPlaceholder(kHash);
  ASSERT_EQ(decode.size(), 1U);
  ASSERT_EQ(decode[0].kind, Kind::DecodePlaceholder);

  EXPECT_EQ(lifecycle.loadFailed(1, kHash, kDecode, kRemote),
            effects({{.kind = Kind::DeliverFailure},
                     {.kind = Kind::ClearImage},
                     {.kind = Kind::EmitCompleted}}));
  // A decode that finishes after the failure must not appear either.
  EXPECT_FALSE(lifecycle.placeholderDecoded(decode[0].value, kHash));
  // Re-applying brings no placeholder back (it only clears, idempotently).
  EXPECT_EQ(lifecycle.applyPlaceholder(kHash), effects({{.kind = Kind::ClearImage}}));
}

TEST(ViewLifecycle, FailureKeepsThePlaceholderWhenAsked) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kHashKeptOnFailure);
  const auto decode = lifecycle.applyPlaceholder(kHashKeptOnFailure);
  EXPECT_EQ(lifecycle.loadFailed(1, kHashKeptOnFailure, kDecode, kRemote),
            effects({{.kind = Kind::DeliverFailure}, {.kind = Kind::EmitCompleted}}));
  EXPECT_TRUE(lifecycle.placeholderDecoded(decode[0].value, kHashKeptOnFailure));
}

TEST(ViewLifecycle, DroppingShowPlaceholderOnFailureClearsTheKeptPlaceholder) {
  // The failure kept the placeholder; the app then turns the flag off.
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kHashKeptOnFailure);
  const auto decode = lifecycle.applyPlaceholder(kHashKeptOnFailure);
  (void)lifecycle.loadFailed(1, kHashKeptOnFailure, kDecode, kRemote);

  EXPECT_EQ(lifecycle.applyPlaceholder(kHash), effects({{.kind = Kind::ClearImage}}));
  EXPECT_FALSE(lifecycle.placeholderDecoded(decode[0].value, kHash));
}

TEST(ViewLifecycle, SettingShowPlaceholderOnFailureShowsThePlaceholderOverAFailure) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kHash);
  (void)lifecycle.applyPlaceholder(kHash);
  (void)lifecycle.loadFailed(1, kHash, kDecode, kRemote);

  const auto decode = lifecycle.applyPlaceholder(kHashKeptOnFailure);
  ASSERT_EQ(decode.size(), 1U);
  EXPECT_EQ(decode[0].kind, Kind::DecodePlaceholder);
}

TEST(ViewLifecycle, FailureSwapsAKeptPreviousImageForThePlaceholder) {
  auto lifecycle = loaded();
  (void)lifecycle.reload(false, true, true, kHashKeptOnFailure);
  const auto failed = lifecycle.loadFailed(2, kHashKeptOnFailure, kDecode, kRemote);
  ASSERT_EQ(failed.size(), 4U);
  EXPECT_EQ(failed[0].kind, Kind::DeliverFailure);
  EXPECT_EQ(failed[1].kind, Kind::ClearImage);
  EXPECT_EQ(failed[2].kind, Kind::DecodePlaceholder);
  EXPECT_EQ(failed[3].kind, Kind::EmitCompleted);
  EXPECT_TRUE(lifecycle.placeholderDecoded(failed[2].value, kHashKeptOnFailure));
}

TEST(ViewLifecycle, ALoadedImageIsNotReplacedByAPlaceholder) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kHash);
  const auto decode = lifecycle.applyPlaceholder(kHash);
  (void)lifecycle.loadSucceeded(1);
  EXPECT_FALSE(lifecycle.placeholderDecoded(decode[0].value, kHash));
  EXPECT_TRUE(lifecycle.applyPlaceholder(kHash).empty());
}

TEST(ViewLifecycle, ANewerPlaceholderSupersedesAnOlderDecode) {
  ViewLifecycle lifecycle;
  const auto first = lifecycle.applyPlaceholder(kHash);
  const auto second = lifecycle.applyPlaceholder(kHash);
  EXPECT_FALSE(lifecycle.placeholderDecoded(first[0].value, kHash));
  EXPECT_TRUE(lifecycle.placeholderDecoded(second[0].value, kHash));
}

TEST(ViewLifecycle, ARemovedPlaceholderPropClearsTheView) {
  ViewLifecycle lifecycle;
  const auto decode = lifecycle.applyPlaceholder(kHash);
  EXPECT_EQ(lifecycle.applyPlaceholder(kNoPlaceholder), effects({{.kind = Kind::ClearImage}}));
  EXPECT_FALSE(lifecycle.placeholderDecoded(decode[0].value, kNoPlaceholder));
}

TEST(ViewLifecycle, AMemoryCacheKeyPlaceholderIsLookedUpNotDecoded) {
  ViewLifecycle lifecycle;
  EXPECT_EQ(lifecycle.applyPlaceholder({.placeholder = PlaceholderKind::MemoryCacheKey}),
            effects({{.kind = Kind::ShowCachedPlaceholder}}));
}

TEST(ViewLifecycle, RecycleResetsEverythingAndTellsJsNothing) {
  auto lifecycle = loaded();
  (void)lifecycle.reload(false, true, true, kHash);
  const auto generation = lifecycle.placeholderGeneration;
  EXPECT_EQ(lifecycle.recycle(),
            effects({{.kind = Kind::CancelLoad}, {.kind = Kind::ClearImage}}));
  EXPECT_EQ(lifecycle.inFlight, 0);
  EXPECT_EQ(lifecycle.showingState(), Showing::NoImage);
  EXPECT_GT(lifecycle.placeholderGeneration, generation);
  // The next life's first load keeps nothing, whatever its recyclingKey.
  EXPECT_EQ(lifecycle.reload(false, false, true, kHash)[0].kind, Kind::ClearImage);
}

TEST(ViewLifecycle, DropStopsTheLoadAndAnyDecode) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kHash);
  const auto decode = lifecycle.applyPlaceholder(kHash);
  EXPECT_EQ(lifecycle.drop(), effects({{.kind = Kind::CancelLoad}}));
  EXPECT_FALSE(lifecycle.placeholderDecoded(decode[0].value, kHash));
  EXPECT_TRUE(lifecycle.loadSucceeded(1).empty());
  EXPECT_TRUE(lifecycle.drop().empty());
}

TEST(ViewLifecycle, AnUpgradeStartsOnlyOverALoadedImage) {
  ViewLifecycle fresh;
  EXPECT_EQ(fresh.startUpgrade(), 0);  // nothing loaded

  ViewLifecycle loading;
  (void)loading.reload(false, false, true, kNoPlaceholder);
  EXPECT_EQ(loading.startUpgrade(), 0);  // the load in flight is sized for the view anyway

  ViewLifecycle failed;
  (void)failed.reload(false, false, true, kNoPlaceholder);
  (void)failed.loadFailed(failed.inFlight, kNoPlaceholder, kDecode, kRemote);
  EXPECT_EQ(failed.startUpgrade(), 0);  // nothing to sharpen

  auto lifecycle = loaded();
  const auto token = lifecycle.startUpgrade();
  EXPECT_NE(token, 0);
  EXPECT_TRUE(lifecycle.isUpgrading(token));
  EXPECT_FALSE(lifecycle.isInFlight(token));  // so its progress reaches nobody
  EXPECT_EQ(lifecycle.startUpgrade(), 0);  // one at a time
}

TEST(ViewLifecycle, AnUpgradeIsSilentWhicheverWayItEnds) {
  auto lifecycle = loaded();
  const auto token = lifecycle.startUpgrade();
  EXPECT_TRUE(lifecycle.upgradeSucceeded(token));
  EXPECT_EQ(lifecycle.showingState(), Showing::LoadedImage);
  EXPECT_FALSE(lifecycle.upgradeSucceeded(token));  // heard once

  const auto failing = lifecycle.startUpgrade();
  lifecycle.upgradeFailed(failing);
  EXPECT_EQ(lifecycle.showingState(), Showing::LoadedImage);  // the image stays
  EXPECT_NE(lifecycle.startUpgrade(), 0);  // and a later growth may try again
}

TEST(ViewLifecycle, AReloadCancelsAnUpgradeWithoutAnEvent) {
  auto lifecycle = loaded();
  const auto token = lifecycle.startUpgrade();
  EXPECT_EQ(lifecycle.reload(false, true, true, kNoPlaceholder),
            effects({{.kind = Kind::CancelLoad}, {.kind = Kind::StartLoad, .value = token + 1}}));
  EXPECT_FALSE(lifecycle.upgradeSucceeded(token));  // a late callback shows nothing
}

TEST(ViewLifecycle, RecycleAndDropCancelAnUpgrade) {
  auto recycled = loaded();
  (void)recycled.startUpgrade();
  EXPECT_EQ(recycled.recycle(), effects({{.kind = Kind::CancelLoad}, {.kind = Kind::ClearImage}}));
  EXPECT_EQ(recycled.upgrading, 0);

  auto dropped = loaded();
  (void)dropped.startUpgrade();
  EXPECT_EQ(dropped.drop(), effects({{.kind = Kind::CancelLoad}}));
  EXPECT_EQ(dropped.upgrading, 0);
}

// ---------------------------------------------------------------------------
// Retry after a network failure.

// A load that failed with `code`; returns the failed lifecycle.
ViewLifecycle failedWith(LoadErrorCode code, const LifecycleProps& props,
                         bool remoteSource = kRemote) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, props);
  (void)lifecycle.applyPlaceholder(props);
  (void)lifecycle.loadFailed(lifecycle.inFlight, props, code, remoteSource);
  return lifecycle;
}

TEST(ViewLifecycleRetry, ANetworkFailureRetriesAsANewLoad) {
  auto lifecycle = failedWith(kNetwork, kNoPlaceholder);
  EXPECT_EQ(lifecycle.retry(kNoPlaceholder),
            effects({{.kind = Kind::ClearImage}, {.kind = Kind::StartLoad, .value = 2}}));
  EXPECT_TRUE(lifecycle.isInFlight(2));
  EXPECT_EQ(lifecycle.showingState(), Showing::NoImage);
  EXPECT_EQ(lifecycle.loadSucceeded(2),
            effects({{.kind = Kind::DeliverSuccess}, {.kind = Kind::EmitCompleted}}));
}

TEST(ViewLifecycleRetry, OtherFailuresAreNotRetried) {
  for (const auto code : {LoadErrorCode::Decode, LoadErrorCode::NotCached, LoadErrorCode::Http,
                          LoadErrorCode::Unknown, LoadErrorCode::InvalidRequest}) {
    auto lifecycle = failedWith(code, kNoPlaceholder);
    EXPECT_TRUE(lifecycle.retry(kNoPlaceholder).empty()) << static_cast<int>(code);
  }
}

TEST(ViewLifecycleRetry, ALocalSourceIsNotRetried) {
  // A missing file reads as an I/O (`Network`) failure, but no trip to the
  // background or back can bring it.
  auto lifecycle = failedWith(kNetwork, kNoPlaceholder, /*remoteSource=*/false);
  EXPECT_EQ(lifecycle.showingState(), Showing::Failed);
  EXPECT_TRUE(lifecycle.retry(kNoPlaceholder).empty());
}

TEST(ViewLifecycleRetry, AnInvalidRequestIsNotRetried) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, false, kNoPlaceholder);
  EXPECT_TRUE(lifecycle.retry(kNoPlaceholder).empty());
}

TEST(ViewLifecycleRetry, EachFailureIsRetriedOnce) {
  auto lifecycle = failedWith(kNetwork, kNoPlaceholder);
  ASSERT_FALSE(lifecycle.retry(kNoPlaceholder).empty());
  EXPECT_TRUE(lifecycle.retry(kNoPlaceholder).empty()) << "a load is already in flight";
  (void)lifecycle.loadFailed(lifecycle.inFlight, kNoPlaceholder, kNetwork, kRemote);
  // The retry's own failure may be retried later, by a later call.
  EXPECT_FALSE(lifecycle.retry(kNoPlaceholder).empty());
}

TEST(ViewLifecycleRetry, ARetryBringsBackTheRemovedPlaceholder) {
  auto lifecycle = failedWith(kNetwork, kHash);
  const auto retried = lifecycle.retry(kHash);
  ASSERT_EQ(retried.size(), 2U);
  EXPECT_EQ(retried[0].kind, Kind::DecodePlaceholder);
  EXPECT_EQ(retried[1].kind, Kind::StartLoad);
  EXPECT_TRUE(lifecycle.placeholderDecoded(retried[0].value, kHash));
}

TEST(ViewLifecycleRetry, AKeptPlaceholderStaysUpWhileRetrying) {
  auto lifecycle = failedWith(kNetwork, kHashKeptOnFailure);
  EXPECT_EQ(lifecycle.retry(kHashKeptOnFailure),
            effects({{.kind = Kind::StartLoad, .value = 2}}));
}

TEST(ViewLifecycleRetry, AReloadRecycleOrDropForgetsTheFailure) {
  auto reloaded = failedWith(kNetwork, kNoPlaceholder);
  (void)reloaded.reload(false, false, false, kNoPlaceholder);
  EXPECT_TRUE(reloaded.retry(kNoPlaceholder).empty());

  auto recycled = failedWith(kNetwork, kNoPlaceholder);
  (void)recycled.recycle();
  EXPECT_TRUE(recycled.retry(kNoPlaceholder).empty());

  auto dropped = failedWith(kNetwork, kNoPlaceholder);
  (void)dropped.drop();
  EXPECT_TRUE(dropped.retry(kNoPlaceholder).empty());
}

// Every order of events, to a bounded depth.
//
// Drives a simulated view through every step sequence up to `kDepth`,
// checking the visible rules after each. Its loader may call back once for
// any load ever started, cancelled or not (the weakest adapter allowed).

struct SimulatedView {
  enum class Screen { Blank, Placeholder, Image };

  ViewLifecycle lifecycle;
  LifecycleProps props;
  Screen screen = Screen::Blank;
  // The request the props name now; a reload makes a new one.
  int request = 0;
  // The request each load or upgrade was for; images are identified by
  // request, not token.
  std::map<std::int64_t, int> requestOf;
  // Screen::Image: the request whose image is up.
  int imageOf = -1;
  // onStart events not yet followed by an onCompletion.
  int openEvents = 0;
  std::set<std::int64_t> awaitingCallback;
  std::set<std::int64_t> awaitingUpgrade;
  std::set<std::int64_t> decodes;

  void perform(const LifecycleEffects& list, std::int64_t callbackToken, bool completeInsideLoad) {
    for (const auto& effect : list) {
      switch (effect.kind) {
        case Kind::CancelLoad:
        case Kind::DeliverFailure:
          break;
        case Kind::DeliverInvalidRequest:
          // An unstartable request has no onStart (RFC 4.4a); count its
          // completion as paired.
          ++openEvents;
          break;
        case Kind::ClearImage:
          screen = Screen::Blank;
          break;
        case Kind::EmitCancelled:
        case Kind::EmitCompleted:
          --openEvents;
          break;
        case Kind::StartLoad:
          ++openEvents;
          requestOf[effect.value] = request;
          if (completeInsideLoad) {
            perform(lifecycle.loadSucceeded(effect.value), effect.value, false);
          } else {
            awaitingCallback.insert(effect.value);
          }
          break;
        case Kind::DeliverSuccess:
          screen = Screen::Image;
          imageOf = requestOf[callbackToken];
          break;
        case Kind::ShowCachedPlaceholder:
          screen = Screen::Placeholder;
          break;
        case Kind::DecodePlaceholder:
          decodes.insert(effect.value);
          break;
      }
    }
  }

  void reload(bool recyclingKeyChanged, bool requestValid, bool completeInsideLoad) {
    ++request;
    perform(lifecycle.reload(recyclingKeyChanged, screen == Screen::Image, requestValid, props), 0,
            completeInsideLoad);
    perform(lifecycle.applyPlaceholder(props), 0, false);
  }

  // The view grew: startUpgrade, then a load that may call back inline.
  void upgrade(bool completeInsideLoad) {
    const auto token = lifecycle.startUpgrade();
    if (token == 0) {
      return;
    }
    requestOf[token] = request;
    if (completeInsideLoad) {
      upgradeSucceeded(token);
    } else {
      awaitingUpgrade.insert(token);
    }
  }

  void upgradeSucceeded(std::int64_t token) {
    if (lifecycle.upgradeSucceeded(token)) {
      screen = Screen::Image;
      imageOf = requestOf[token];
    }
  }

  // Empty when every rule holds, otherwise the rule that broke.
  [[nodiscard]] std::string brokenRule() const {
    const auto showing = lifecycle.showingState();
    if (openEvents != (lifecycle.inFlight != 0 ? 1 : 0)) {
      return "EventsBalanced";
    }
    if (showing == Showing::LoadedImage && !(screen == Screen::Image && imageOf == request)) {
      return "LoadedImageStays";
    }
    if (lifecycle.upgrading != 0 &&
        !(showing == Showing::LoadedImage && requestOf.at(lifecycle.upgrading) == request)) {
      return "UpgradeOnlyOverLoadedImage";
    }
    if (lifecycle.upgrading != 0 && lifecycle.inFlight != 0) {
      return "UpgradeNeverBesideALoad";
    }
    if (screen == Screen::Image && showing != Showing::LoadedImage &&
        showing != Showing::PreviousImage) {
      return "NoWrongImage";
    }
    if (showing == Showing::PreviousImage &&
        !(lifecycle.inFlight != 0 && screen == Screen::Image)) {
      return "PreviousImageOnlyWhileLoading";
    }
    if (showing == Showing::Failed && !props.showPlaceholderOnFailure && screen != Screen::Blank) {
      return "FailedViewIsEmpty";
    }
    if (lifecycle.retryable != 0 &&
        (showing != Showing::Failed || lifecycle.inFlight != 0 || lifecycle.upgrading != 0)) {
      return "RetryOnlyFromAFailure";
    }
    return {};
  }
};

constexpr int kDepth = 6;

void explore(const SimulatedView& view, int depth, std::string& path, std::string& failure) {
  if (!failure.empty()) {
    return;
  }
  if (const auto rule = view.brokenRule(); !rule.empty()) {
    failure = rule + " after:" + path;
    return;
  }
  if (depth == kDepth) {
    return;
  }
  const auto step = [&](const std::string& name, const auto& action) {
    SimulatedView next = view;
    action(next);
    const auto length = path.size();
    path += " " + name;
    explore(next, depth + 1, path, failure);
    path.resize(length);
  };

  for (const bool recyclingKeyChanged : {false, true}) {
    for (const bool requestValid : {false, true}) {
      for (const bool inside : {false, true}) {
        if (inside && !requestValid) {
          continue;
        }
        step(std::string("reload(") + (recyclingKeyChanged ? "newKey" : "sameKey") +
                 (requestValid ? "" : ",invalid") + (inside ? ",completesInside" : "") + ")",
             [&](SimulatedView& v) { v.reload(recyclingKeyChanged, requestValid, inside); });
      }
    }
  }
  for (const auto token : view.awaitingCallback) {
    step("succeeds#" + std::to_string(token), [&](SimulatedView& v) {
      v.awaitingCallback.erase(token);
      v.perform(v.lifecycle.loadSucceeded(token), token, false);
    });
    for (const auto code : {kDecode, kNetwork}) {
      step(std::string(code == kNetwork ? "failsNetwork#" : "fails#") + std::to_string(token),
           [&](SimulatedView& v) {
             v.awaitingCallback.erase(token);
             v.perform(v.lifecycle.loadFailed(token, v.props, code, kRemote), token, false);
           });
    }
  }
  // Foregrounding, or a failure that spanned a trip to the background.
  for (const bool inside : {false, true}) {
    step(std::string("retry") + (inside ? "(completesInside)" : ""),
         [&](SimulatedView& v) { v.perform(v.lifecycle.retry(v.props), 0, inside); });
  }
  for (const bool inside : {false, true}) {
    step(std::string("upgrade") + (inside ? "(completesInside)" : ""),
         [&](SimulatedView& v) { v.upgrade(inside); });
  }
  for (const auto token : view.awaitingUpgrade) {
    step("upgradeSucceeds#" + std::to_string(token), [&](SimulatedView& v) {
      v.awaitingUpgrade.erase(token);
      v.upgradeSucceeded(token);
    });
    step("upgradeFails#" + std::to_string(token), [&](SimulatedView& v) {
      v.awaitingUpgrade.erase(token);
      v.lifecycle.upgradeFailed(token);
    });
  }
  for (const auto generation : view.decodes) {
    step("decoded#" + std::to_string(generation), [&](SimulatedView& v) {
      v.decodes.erase(generation);
      if (v.lifecycle.placeholderDecoded(generation, v.props)) {
        v.screen = SimulatedView::Screen::Placeholder;
      }
    });
  }
  for (const auto kind :
       {PlaceholderKind::None, PlaceholderKind::Hash, PlaceholderKind::MemoryCacheKey}) {
    if (kind == view.props.placeholder) {
      continue;
    }
    step("placeholder=" + std::to_string(static_cast<int>(kind)), [&](SimulatedView& v) {
      v.props.placeholder = kind;
      v.perform(v.lifecycle.applyPlaceholder(v.props), 0, false);
    });
  }
  step("recycle", [&](SimulatedView& v) {
    v.perform(v.lifecycle.recycle(), 0, false);
    // The component that was listening is gone, with its open events.
    v.openEvents = 0;
    v.props.placeholder = PlaceholderKind::None;
  });
}

TEST(ViewLifecycle, RulesHoldInEveryOrderOfEvents) {
  for (const bool showPlaceholderOnFailure : {false, true}) {
    SimulatedView view;
    view.props.showPlaceholderOnFailure = showPlaceholderOnFailure;
    std::string path;
    std::string failure;
    explore(view, 0, path, failure);
    EXPECT_TRUE(failure.empty()) << failure;
  }
}

}  // namespace
}  // namespace turboimage
