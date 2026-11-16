// TurboImage core: download-progress event throttling.
//
// Loaders report progress at very different rates (Nuke per URLSession
// chunk, OkHttp per read() call). Forwarding every callback would flood the
// JS thread with `onProgress` events, and the number of events JS sees would
// differ by platform. Both views run each update through this one rule
// instead (RFC rule 3).
//
// Ownership/threading: a plain value type holding per-load state. Each view
// owns one per load and uses it on the main thread only.

#pragma once

#include <cstdint>

namespace turboimage {

// Per-load throttle state. Three integers so the Android view can keep it
// in a LongArray and pass it through JNI, keeping the logic only here.
struct ProgressThrottle {
  // Bytes between reports when the total size is unknown (no
  // Content-Length): ~16 events per MiB.
  static constexpr std::int64_t kUnknownTotalStepBytes = 64 * 1024;

  std::int64_t lastPercent = -1;
  std::int64_t lastReportedBytes = -1;
  std::int64_t reportedCompletion = 0;  // 0/1; int64 for the JNI LongArray

  // Returns true if this update should become an `onProgress` event:
  //   * known total: whenever the whole-percent value increases, and always
  //     once for completion (completed >= total);
  //   * unknown total (<= 0): every kUnknownTotalStepBytes.
  // Updates that go backwards (a retried request restarting) are dropped
  // until they pass the last reported point.
  [[nodiscard]] bool shouldReport(std::int64_t completed, std::int64_t total);

  // Called once when the load succeeds, with the last total seen. Returns
  // true if a final {total, total} event must still be emitted, i.e. the
  // total is known and completion was not reported yet.
  //
  // Why: a decoder may stop reading once the image is complete (Coil
  // decoding a `noCache` response straight from the network stream stops
  // at the JPEG end marker), so the byte count can end short of
  // Content-Length on Android while Nuke on iOS always reads to EOF. A
  // successful load is complete from the app's point of view, so both
  // platforms end with 100%.
  [[nodiscard]] bool finish(std::int64_t total);
};

}  // namespace turboimage
