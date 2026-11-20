# 0008: SVG on iOS uses the private CoreSVG framework

Status: accepted

## Context

iOS has no public SVG decoder. 1.x used Apple's private CoreSVG, which
gives a vector `UIImage` that stays sharp at any size.

## Decision

Keep CoreSVG. Every symbol is looked up and checked, so a missing one
fails the load as `decode` instead of crashing.

## Consequences

- App Review risk, accepted knowingly.
- A vector image has no pixels, so the core resolves a second decode target for it (`vectorDecode`), and the adapter draws it at that size before a processor runs.
- Android uses `coil-svg` (AndroidSVG), so the two platforms render through different engines.

More: RFC §4.5b, §4.5c.
