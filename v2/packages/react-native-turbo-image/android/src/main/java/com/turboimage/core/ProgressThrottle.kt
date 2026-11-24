package com.turboimage.core

/** Per-load progress throttle; the rule is in the C++ core. Main thread only. */
class ProgressThrottle {
  // lastPercent, lastReportedBytes, reportedCompletion (C++ defaults).
  private val state = longArrayOf(-1L, -1L, 0L)

  fun shouldReport(completed: Long, total: Long): Boolean =
    TurboImageCore.nativeShouldReportProgress(state, completed, total)

  /** True if a final {total, total} event must still be emitted on success. */
  fun finish(total: Long): Boolean = TurboImageCore.nativeFinishProgress(state, total)
}
