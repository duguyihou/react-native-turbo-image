#include "turboimage/Progress.h"

namespace turboimage {

bool ProgressThrottle::shouldReport(std::int64_t completed, std::int64_t total) {
  if (completed < 0) {
    return false;
  }

  if (total > 0) {
    if (completed >= total) {
      // Completion is reported exactly once, even if the loader repeats it.
      if (reportedCompletion != 0) {
        return false;
      }
      reportedCompletion = 1;
      lastPercent = 100;
      return true;
    }
    // Integer maths: no float rounding differences between platforms.
    const std::int64_t percent = completed * 100 / total;
    if (percent > lastPercent) {
      lastPercent = percent;
      return true;
    }
    return false;
  }

  // Unknown total: report the first update, then every step.
  if (lastReportedBytes < 0 ||
      completed - lastReportedBytes >= kUnknownTotalStepBytes) {
    lastReportedBytes = completed;
    return true;
  }
  return false;
}

bool ProgressThrottle::finish(std::int64_t total) {
  if (total <= 0 || reportedCompletion != 0) {
    return false;
  }
  reportedCompletion = 1;
  lastPercent = 100;
  return true;
}

}  // namespace turboimage
