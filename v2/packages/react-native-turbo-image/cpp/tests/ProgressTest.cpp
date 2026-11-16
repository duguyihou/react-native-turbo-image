#include <gtest/gtest.h>

#include "turboimage/Progress.h"

namespace turboimage {
namespace {

TEST(ProgressThrottle, ReportsEachNewWholePercentOnly) {
  ProgressThrottle throttle;
  EXPECT_TRUE(throttle.shouldReport(0, 1000));    // 0%
  EXPECT_FALSE(throttle.shouldReport(5, 1000));   // still 0%
  EXPECT_TRUE(throttle.shouldReport(10, 1000));   // 1%
  EXPECT_FALSE(throttle.shouldReport(19, 1000));  // still 1%
  EXPECT_TRUE(throttle.shouldReport(500, 1000));  // jumps are fine
}

TEST(ProgressThrottle, CapsEventsAtAboutOneHundredPerLoad) {
  ProgressThrottle throttle;
  int events = 0;
  for (std::int64_t bytes = 0; bytes <= 10'000'000; bytes += 997) {
    events += throttle.shouldReport(bytes, 10'000'000) ? 1 : 0;
  }
  events += throttle.shouldReport(10'000'000, 10'000'000) ? 1 : 0;
  EXPECT_LE(events, 101);
  EXPECT_GE(events, 100);
}

TEST(ProgressThrottle, ReportsCompletionExactlyOnce) {
  ProgressThrottle throttle;
  EXPECT_TRUE(throttle.shouldReport(999, 1000));
  EXPECT_TRUE(throttle.shouldReport(1000, 1000));
  EXPECT_FALSE(throttle.shouldReport(1000, 1000));
}

TEST(ProgressThrottle, IgnoresUpdatesThatGoBackwards) {
  ProgressThrottle throttle;
  EXPECT_TRUE(throttle.shouldReport(500, 1000));
  EXPECT_FALSE(throttle.shouldReport(100, 1000));  // a retry restarting
  EXPECT_FALSE(throttle.shouldReport(500, 1000));
  EXPECT_TRUE(throttle.shouldReport(510, 1000));
}

TEST(ProgressThrottle, UnknownTotalReportsEveryStep) {
  ProgressThrottle throttle;
  constexpr auto step = ProgressThrottle::kUnknownTotalStepBytes;
  EXPECT_TRUE(throttle.shouldReport(1, -1));
  EXPECT_FALSE(throttle.shouldReport(step, -1));
  EXPECT_TRUE(throttle.shouldReport(step + 1, -1));
  EXPECT_FALSE(throttle.shouldReport(step + 2, 0));
}

TEST(ProgressThrottle, RejectsNegativeProgress) {
  ProgressThrottle throttle;
  EXPECT_FALSE(throttle.shouldReport(-1, 100));
}

}  // namespace
}  // namespace turboimage
