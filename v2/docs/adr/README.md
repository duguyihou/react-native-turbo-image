# Decision records

One record per choice that shaped TurboImage 2.0: the situation, what was
decided, and what it costs. They explain *why*; how a feature behaves in
detail is in [RFC 0001](../rfc/0001-turbo-image-2-native-toolchain.md), and
the overview is [`architecture.md`](../architecture.md).

A record is not edited when the decision changes. Add a new one and mark the
old one superseded.

| | Decision |
|---|---|
| [0001](0001-core-owns-request-semantics.md) | The C++ core owns what a request means |
| [0002](0002-disk-cache-is-authoritative.md) | TurboImage's disk cache is authoritative; HTTP freshness is opt-in |
| [0003](0003-plain-objc-seam-on-ios.md) | The iOS seam is plain Objective-C, and the adapter is found by name |
| [0004](0004-android-adapter-displays-the-image.md) | On Android the adapter displays the image; on iOS the view does |
| [0005](0005-core-inside-the-npm-package.md) | The core lives inside the npm package |
| [0006](0006-nuke-as-a-vendored-xcframework.md) | CocoaPods gets Nuke as a vendored xcframework; CocoaPods stays the default |
| [0007](0007-processors-and-placeholders-in-the-core.md) | Processors and placeholders are implemented once, in the core |
| [0008](0008-private-coresvg-on-ios.md) | SVG on iOS uses the private CoreSVG framework |
| [0009](0009-js-container-for-rounded-and-indicator.md) | `rounded` and `indicator` use a JS container view |
| [0010](0010-view-lifecycle-in-the-core.md) | The view lifecycle is a state machine in the core |
| [0011](0011-local-fixture-server.md) | The smoke suite loads from a local fixture server |
| [0012](0012-nuke-plays-animations-on-ios.md) | On iOS the adapter plays animations, in an image view it supplies |
