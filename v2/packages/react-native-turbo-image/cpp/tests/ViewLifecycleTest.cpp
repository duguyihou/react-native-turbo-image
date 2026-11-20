#include <gtest/gtest.h>

#include <cstdint>
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
  EXPECT_TRUE(lifecycle.loadFailed(1, kNoPlaceholder).empty());
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
  // The first load calling back late (an adapter that did not honour the
  // cancel) must not touch the view.
  EXPECT_TRUE(lifecycle.loadSucceeded(1).empty());
  EXPECT_TRUE(lifecycle.loadFailed(1, kNoPlaceholder).empty());
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
  (void)failed.loadFailed(1, kHashKeptOnFailure);
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

  EXPECT_EQ(lifecycle.loadFailed(1, kHash),
            effects({{.kind = Kind::DeliverFailure},
                     {.kind = Kind::ClearImage},
                     {.kind = Kind::EmitCompleted}}));
  // A decode that finishes after the failure must not appear either.
  EXPECT_FALSE(lifecycle.placeholderDecoded(decode[0].value, kHash));
  EXPECT_TRUE(lifecycle.applyPlaceholder(kHash).empty());
}

TEST(ViewLifecycle, FailureKeepsThePlaceholderWhenAsked) {
  ViewLifecycle lifecycle;
  (void)lifecycle.reload(false, false, true, kHashKeptOnFailure);
  const auto decode = lifecycle.applyPlaceholder(kHashKeptOnFailure);
  EXPECT_EQ(lifecycle.loadFailed(1, kHashKeptOnFailure),
            effects({{.kind = Kind::DeliverFailure}, {.kind = Kind::EmitCompleted}}));
  EXPECT_TRUE(lifecycle.placeholderDecoded(decode[0].value, kHashKeptOnFailure));
}

TEST(ViewLifecycle, FailureSwapsAKeptPreviousImageForThePlaceholder) {
  auto lifecycle = loaded();
  (void)lifecycle.reload(false, true, true, kHashKeptOnFailure);
  const auto failed = lifecycle.loadFailed(2, kHashKeptOnFailure);
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

// ---------------------------------------------------------------------------
// Every order of events, to a bounded depth.
//
// The tests above each walk one path. The bugs this state machine exists to
// prevent are in the orderings nobody thought of, so this drives a simulated
// view through every sequence of steps up to `kDepth` and checks, after each
// one, the rules a user or JS would notice being broken.
//
// The simulated view shows images itself (as the iOS view does) and its
// loader may call back for any load ever started, cancelled or not, once.
// That is the weakest adapter the seam allows, so the token guard carries
// the whole weight.

struct SimulatedView {
  enum class Screen { Blank, Placeholder, Image };

  ViewLifecycle lifecycle;
  LifecycleProps props;
  Screen screen = Screen::Blank;
  // Screen::Image: the token of the load whose image is up.
  std::int64_t imageOf = 0;
  // onStart events not yet followed by an onCompletion.
  int openEvents = 0;
  std::set<std::int64_t> awaitingCallback;
  std::set<std::int64_t> decodes;

  void perform(const LifecycleEffects& list, std::int64_t callbackToken, bool completeInsideLoad) {
    for (const auto& effect : list) {
      switch (effect.kind) {
        case Kind::CancelLoad:
        case Kind::DeliverFailure:
          break;
        case Kind::DeliverInvalidRequest:
          // A request that cannot start gets onFailure and onCompletion but
          // no onStart (RFC 4.4a). Count its completion as paired, so the
          // balance below is about loads that did start.
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
          if (completeInsideLoad) {
            perform(lifecycle.loadSucceeded(effect.value), effect.value, false);
          } else {
            awaitingCallback.insert(effect.value);
          }
          break;
        case Kind::DeliverSuccess:
          screen = Screen::Image;
          imageOf = callbackToken;
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
    perform(lifecycle.reload(recyclingKeyChanged, screen == Screen::Image, requestValid, props), 0,
            completeInsideLoad);
    perform(lifecycle.applyPlaceholder(props), 0, false);
  }

  // Empty when every rule holds, otherwise the rule that broke.
  [[nodiscard]] std::string brokenRule() const {
    const auto showing = lifecycle.showingState();
    if (openEvents != (lifecycle.inFlight != 0 ? 1 : 0)) {
      return "EventsBalanced";
    }
    if (showing == Showing::LoadedImage &&
        !(screen == Screen::Image && imageOf == lifecycle.lastToken)) {
      return "LoadedImageStays";
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
    step("fails#" + std::to_string(token), [&](SimulatedView& v) {
      v.awaitingCallback.erase(token);
      v.perform(v.lifecycle.loadFailed(token, v.props), token, false);
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
