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
  might loop. `reload`, `recycle` and `drop` forget the failure.
- **`retry(props)`** starts the same request again as a new load, with
  `onStart` … `onCompletion`, so JS sees the view recover. It brings back the
  placeholder the failure removed. Each failure is retried at most once per
  call: a retry that fails again waits for the next call.
- **The views call it at two moments:**
  - when the app returns to the foreground (iOS
    `UIApplicationWillEnterForegroundNotification`, Android `onHostResume`);
  - right after a network failure of a load that began before a trip to the
    background, if the app is in the foreground again. This is the common
    case: iOS delivers the dropped connection after the app resumes, so
    waiting for the next foreground would miss it.

  Each view counts its own trips to the background, so there is no global
  state.

## Consequences

- An app with an error UI driven by `onFailure` shows it briefly, then sees
  `onStart` and the retry's result.
- A view that failed while the app was in the foreground (offline) retries
  on the next return, not when connectivity comes back. Watching
  reachability is a possible follow-up.
  TODO: retry on reachability changes too, if apps ask.
- `ViewLifecycle` has a sixth field, so the Android `LongArray` grows to 6.
- The lifecycle's exhaustive C++ test takes about 17 s instead of 7.5 s,
  and the TLA+ model has a `Retry` step and a `RetryOnlyAfterAFailure` rule.
