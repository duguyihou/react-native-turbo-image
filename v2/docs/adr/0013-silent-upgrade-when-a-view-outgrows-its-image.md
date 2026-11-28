# 0013: A view that outgrows its image reloads it silently

Status: accepted

## Context

Images are decoded no larger than their view, so a view that grows after
its image loaded (a rotation, a card that expands, a split view) draws a
small decode stretched and soft. Until now the only way out was
`allowDownscaling={false}`, which gives up the memory saving everywhere.

Reloading on growth raises three questions: when it is worth it, what JS
hears, and what is on screen meanwhile.

## Decision

The core decides when (`needsLargerDecode`): once the view would draw the
image at more than 1.5× its decoded pixels, and never for an image that
came out smaller than its view, which is the source at its own size. A
ratio rather than any growth, so a view animating its size reloads a few
times, not once per frame.

The lifecycle runs the reload as an **upgrade** (`ViewLifecycle::startUpgrade`),
a load of its own kind:

- Silent: no `onStart`, progress, `onSuccess` or `onCompletion`. The props
  did not change, and the image JS was told about is still the one on
  screen, only sharper.
- Only over a loaded image with nothing in flight, one at a time; the view
  asks again when one succeeds.
- The image stays on screen until the sharper one replaces it, without a
  fade. A failed upgrade leaves it there and is not retried for that
  image.
- A reload, recycle or drop cancels a running upgrade, again silently.

## Consequences

- Apps that count loads or drive a spinner from the events see nothing
  new. In exchange, a failed upgrade is invisible to them too.
- `onSuccess` reports the size of the first decode, not the upgraded one.
- The lifecycle gains a fifth field (`upgrading`), so its JNI `LongArray`
  grows to five, and the lifecycle model gains the `ViewGrows` action and
  the `UpgradeOnlyOverLoadedImage` rule.
- A zoom by `transform` does not change the layout, so a zoomable image
  still needs `allowDownscaling={false}`.
- Not upgraded: requests whose decode does not follow the view
  (`allowDownscaling={false}`, `resize`, `center`, `blur`); on iOS,
  animated images (Nuke's player sizes its frames itself) and SVG (drawn
  sharp at any size). On Android an upgraded animation restarted, so
  animated images are not upgraded there either (amended 2026-11-25).

More: RFC §4.5c ("A view that grows gets a sharper copy");
`cpp/include/turboimage/ImageRequest.h` (`needsLargerDecode`);
`cpp/include/turboimage/ViewLifecycle.h` (upgrades).
