# 0002: TurboImage's disk cache is authoritative; HTTP freshness is opt-in

Status: accepted

## Context

Nuke and Coil treat HTTP caching differently by default, and an image
library used for lists must not refetch because a server sent a short
`max-age`. Some apps do need the server to control freshness.

## Decision

For every policy but one, TurboImage's own disk cache is the only disk
tier and `Cache-Control` is ignored on both platforms. `cachePolicy="urlCache"`
opts one image into an HTTP cache that obeys freshness, revalidation and
`no-store`. That cache is a separate store keyed by URL: nothing it holds is
visible to `cacheOnly`, and the reverse.

## Consequences

- The same image under two policies can be on disk twice.
- The memory tier is shared and never expires within a process, so freshness is checked when an image is not in memory, not on every mount.
- iOS needs a second Nuke pipeline for it, and `URLCache` will not store a response over 5% of its capacity (7.5 MB).
- On Android this relies on Coil's experimental cache-control strategy.

More: RFC §4.2, §4.2a.
