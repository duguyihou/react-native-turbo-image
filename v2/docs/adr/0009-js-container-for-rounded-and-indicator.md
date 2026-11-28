# 0009: `rounded` and `indicator` use a JS container view

Status: accepted; amended 2026-11 for `rounded` (commit `db9eb74`)

## Context

1.x clipped `rounded` in a container and drew the indicator natively,
differently per platform.

## Decision

`indicator` wraps the native view in a React `View`. `rounded` first did too; it is now `borderRadius: 9999` and `overflow: 'hidden'` on the image view's own style, and with `indicator` the container takes the rounding so the spinner is clipped. The
spinner is a plain `ActivityIndicator` driven by `onStart` and
`onCompletion`, shown only if the load still runs after 150 ms.

## Consequences

- One behaviour on both platforms, with no native code.
- Toggling `indicator` on a mounted image adds or removes the container, which remounts the native view and restarts the load (TODO: draw the spinner natively if that matters). Toggling `rounded` changes only the style.
- With a container, `ref`, `testID` and the accessibility props sit on the container, not the image view.
- The image view clips to `borderRadius` itself, so `rounded` dropped the container. That was a breaking change for 2.0: with `rounded` and no `indicator`, `ref` is the image view, not a container. `testID` and the accessibility props stay on the image view, as in 1.x.

More: RFC §4.4b; `src/index.tsx`.
