# 0001: The C++ core owns what a request means

Status: accepted

## Context

1.x interpreted props separately in Swift and Kotlin. The two disagreed on
cache keys, on what a cache policy allowed and on error text: a `cacheOnly`
miss was `Nuke.ImagePipeline.Error error 4` on iOS and `HTTP 504` on Android.

## Decision

One C++20 library, `cpp/`, turns props into a `ResolvedRequest`: the
validated URL and headers, the cache key, which tiers may be read and
written, how large to decode, and the identity of any processing. Views call
`resolveRequest()`; adapters translate the result field by field and make no
policy decision. The same library is compiled into both platforms from one
source tree, inside the npm package ([ADR 0005](0005-core-inside-the-npm-package.md)).

## Consequences

- A behaviour that must match on both platforms is written and tested once, in GoogleTest, with no device.
- Android pays a JNI call per request, and Kotlin and ObjC repeat the core's enum values; `static_assert`s catch a change on the C++ side only.
- The core knows no platform, so an Android-only scheme on iOS is rejected by the loader, not by the core.

More: RFC §4.1, §4.4.
