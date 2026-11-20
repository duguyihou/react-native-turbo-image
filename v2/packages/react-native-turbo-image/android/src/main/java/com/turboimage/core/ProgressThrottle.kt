package com.turboimage.core

/**
 * Per-load progress throttle; the rule lives in the C++ core
 * (`turboimage::ProgressThrottle`). Holds only state, owned by one view and
 * used on the main thread.
 */
class ProgressThrottle {
  // Mirrors ProgressThrottle's fields: lastPercent, lastReportedBytes,
  // reportedCompletion. Initial values match the C++ defaults.
  private val state = longArrayOf(-1L, -1L, 0L)

  fun shouldReport(completed: Long, total: Long): Boolean =
    TurboImageCore.nativeShouldReportProgress(state, completed, total)

  /** True if a final {total, total} event must still be emitted on success. */
  fun finish(total: Long): Boolean = TurboImageCore.nativeFinishProgress(state, total)
}
