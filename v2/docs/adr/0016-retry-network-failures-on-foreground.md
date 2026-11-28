# 0016: A network failure is retried when the app returns to the foreground

Status: accepted.

## Context

When an iOS app is suspended mid-download, the system usually drops the
connection and reports it only once the app is back
(`NSURLErrorNetworkConnectionLost`). Android can lose the network the same
way under Doze. Neither Nuke nor Coil retries, and before this change the
view did not either: it reported `onFailure` with `network` and stayed empty.
An app could not retry the same source itself, because a view reloads only
when its request changes. Users saw images stay blank after coming back to
the app until they scrolled away and back.

Options considered:

- **An imperative `reload()`.** Simpler, but every app would have to wire it to
  app-state events.
- **A silent retry, as the upgrades are ([0013](0013-silent-upgrade-when-a-view-outgrows-its-image.md)).**
  JS has already heard `onFailure`, so a silent success would leave an app's
  error UI up over a loaded image.
- **A retry in the core's lifecycle, with its own events.**

## Decision

- **The core** (`ViewLifecycle`) records whether the failed load may be retried.
  `loadFailed` takes the error code, and only `Network` counts: `NotCached`,
  `Decode` and `InvalidRequest` would fail the same way again, and `Unknown`
  might loop. An error status from the server (a 404) would fail again too,
  so it has its own `Http` code rather than `Network`; a 504 (a gateway
  timeout, or Coil's synthetic one while offline) stays `Network`. A local
  source (`file`, `content`, `android.resource`) is never retried: both
  adapters report a missing or unreadable file as an I/O failure, which reads
  as `Network`, so `loadFailed` also takes whether the source is remote
  (`isRemoteSource`). `reload`, `recycle` and `drop` forget the failure.
- **`retry(props)`** starts the same request again as a new load, with
  `onStart` … `onCompletion`, so JS sees the view recover. It brings back the
  placeholder the failure removed. Each failure is retried at most once per
  call: a retry that fails again waits for the next call.
- **The views call it at three moments:**
  - when the app returns to the foreground (iOS
    `UIApplicationWillEnterForegroundNotification`, Android `onHostResume`);
  - right after a network failure of a load that began before a trip to the
    background, if the app is in the foreground again. This is the common
    case: iOS delivers the dropped connection after the app resumes, so
    waiting for the next foreground would miss it;
  - when the network comes back after being lost, if the app is in the
    foreground (added 2026-11-28). iOS watches the path with one
    `nw_path_monitor` for the process. Android registers one default-network
    callback, only if the app holds `ACCESS_NETWORK_STATE`: the library does
    not declare it, so that every app is not given a permission for this.
    Without it, Android retries on the return to the foreground only.

  Each view counts its own trips to the background. The network watchers
  are the only process-wide state, one subscription each.

## Consequences

- An app with an error UI driven by `onFailure` shows it briefly, then sees
  `onStart` and the retry's result.
- A view that failed while the app was in the foreground (offline) retries
  when the network comes back, except on Android without
  `ACCESS_NETWORK_STATE`, where it waits for the next return to the
  foreground. The platforms differ there on purpose (the permission is the
  app's choice).
- Only a return after a loss counts: the first path update, and a switch
  from one network to another, retry nothing.
- `ViewLifecycle` has a sixth field, so the Android `LongArray` grows to 6.
- The lifecycle's exhaustive C++ test takes about 17 s instead of 7.5 s,
  and the TLA+ model has a `Retry` step and a `RetryOnlyAfterAFailure` rule.
