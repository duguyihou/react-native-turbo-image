# 0009: `rounded` and `indicator` use a JS container view

Status: accepted

## Context

1.x clipped `rounded` in a container and drew the indicator natively,
differently per platform.

## Decision

`rounded` and `indicator` wrap the native view in a React `View`. The
spinner is a plain `ActivityIndicator` driven by `onStart` and
`onCompletion`, shown only if the load still runs after 150 ms.

## Consequences

- One behaviour on both platforms, with no native code.
- Toggling either prop on a mounted image adds or removes the container, which remounts the native view and restarts the load.
- With a container, `ref`, `testID` and the accessibility props sit on the container, not the image view.
- The image view now clips to `borderRadius` itself, so `rounded` no longer needs the container. Dropping it moves `ref` and `testID` to another view, a breaking change that is still to be decided.

More: RFC §4.4b; `src/index.tsx`.
