# 0004: On Android the adapter displays the image; on iOS the view does

Status: accepted

## Context

The two seams could have the same shape: the adapter returns an image and
the view shows it. iOS works that way. On Android three things argue against
it:

- **Layout timing.** Fabric leaves views with `WRAP_CONTENT` params and may start a load before the first layout. The decode size must wait for the laid-out size, and that wait belongs inside the load (a `FlatList` row timed out without it).
- **Coil's target does real work.** With an `ImageView` target Coil cross-fades from the current drawable, skips the fade for memory hits, starts and stops animated drawables with the lifecycle, cancels on detach and restarts on reattach.
- **There is one Android adapter**, and no second one planned.

## Decision

`ImageLoaderAdapter.load` takes the `ImageView`. The adapter displays the
result, cross-fades it and waits for layout; it reports only the image's
size. The view keeps everything else: what stays on screen while a load
runs, placeholders, events. Those decisions are the core's on both platforms
([ADR 0010](0010-view-lifecycle-in-the-core.md)).

## Consequences

- Replacing Coil on Android means re-implementing display, the fade rule and the layout wait, not only fetching and decoding.
- The view cannot veto a paint. A loader that calls back after cancel can put a stale image on screen without asking, so the Android cancel contract carries more weight than the iOS one; the lifecycle model checks the Android view with "cancel is honoured" as an assumption and the iOS view without it.
- The fade duration and `allowHardware` cross the seam as `DisplayOptions`, which the iOS seam has no counterpart for.
- Revisit if a second Android adapter is ever wanted: the seam would then return a drawable and take a size provider.

More: RFC §4.8; `ImageLoaderAdapter.kt`.
