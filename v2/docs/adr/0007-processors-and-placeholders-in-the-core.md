# 0007: Processors and placeholders are implemented once, in the core

Status: accepted

## Context

1.x used each platform's filters (Core Image, RenderScript,
`coil-transformations`) and four separate hash decoders. The same props gave
visibly different images, and the Android transformation library has no
Coil 3 version.

## Decision

`resize`, `blur`, `monochrome` and `tint` are integer arithmetic on
premultiplied RGBA in `Processing.h`; blurhash and thumbhash are decoded by
`Placeholder.h`. The processing description is encoded as a key
(`ti1;w=180;b=6`), and that key is the only thing that crosses to the
adapters: it names the cached variant and is what the processing step is
given, so the cache identity cannot disagree with the pixels.

## Consequences

- Identical output on both platforms; placeholders match the npm reference decoders byte for byte (`#pragma STDC FP_CONTRACT OFF` is required for that).
- No GPU: a 12 MP blur takes about 270 ms on an M-series host, on a background queue.
- Android copies the bitmap about five times on the way through JNI.
- Processors apply to the first frame of an animation, and the result is static.

More: RFC §4.5, §4.5a.
