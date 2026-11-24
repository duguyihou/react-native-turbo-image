// TurboImage core: download-progress throttling, so both platforms emit
// the same `onProgress` events whatever rate their loader reports at
// (RFC rule 3).
//
// Plain value type; each view owns one per load, main thread only.

#pragma once

#include <cstdint>

namespace turboimage {

// Per-load throttle state. Three int64s so Android can keep it in a
// LongArray across JNI.
struct ProgressThrottle {
  // Report step when the total is unknown (no Content-Length).
  static constexpr std::int64_t kUnknownTotalStepBytes = 64 * 1024;

  std::int64_t lastPercent = -1;
  std::int64_t lastReportedBytes = -1;
  std::int64_t reportedCompletion = 0;  // 0/1; int64 for the JNI LongArray

  // Whether this update becomes an `onProgress` event: on each whole-percent
  // increase and once at completion (known total), or every
  // kUnknownTotalStepBytes (unknown total). Backwards updates (a retry) are
  // dropped until they pass the last reported point.
  [[nodiscard]] bool shouldReport(std::int64_t completed, std::int64_t total);

  // On success: true if a final {total, total} event is still owed. A
  // decoder may stop reading before Content-Length (Coil at a JPEG end
  // marker), but a successful load always ends at 100%.
  [[nodiscard]] bool finish(std::int64_t total);
};

}  // namespace turboimage
