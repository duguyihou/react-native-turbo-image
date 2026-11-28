# 0014: The loader seam is internal; apps cannot replace the loader

Status: accepted. Amends [0003](0003-plain-objc-seam-on-ios.md): the seam
stays plain Objective-C and the adapter is still found by name, but an app
no longer assigns `sharedLoader`.

## Context

Rule 1 promised apps a replaceable loader: `TIImageLoaderRegistry.sharedLoader`
on iOS, `TurboImageLoaders.set` on Android. Nothing used it.

- There is one adapter per platform, and [0004](0004-android-adapter-displays-the-image.md) says no second Android adapter is planned. That seam is shaped around Coil's `ImageView` target, so a different loader would have had to rebuild Coil's display behaviour anyway.
- The promise cost code. Both seams carried defaults so that "an adapter written before X keeps compiling" (`loadPlaceholder`, `imageSize`, the optional `imageSizeForRequest:`), for adapters that do not exist.
- It left two behaviour gaps. A view made under a replaced loader keeps that loader's image view.
- Each public method on the seam would be a compatibility promise for the life of 2.x.

The v2 audit (`docs/audit/`) named this the largest source of speculative
complexity.

## Decision

The seam stays, as internal structure. It exists for two reasons:

- On iOS, the view is ObjC++ and the adapter is Swift ([0003](0003-plain-objc-seam-on-ios.md)).
- On both platforms, the view tests drive a view with a fake loader.

It is no longer an extension point:

- **Android:** `ImageLoaderAdapter`, `LoadHandle`, `CoilImageLoaderAdapter`, `TurboImageLoaders` and `CacheSizes` are `internal`. `TurboImageView`'s constructor is `internal`. `TurboImageLoaders.set` is gone; views get their loader from the constructor, which is how the view tests pass the fake.
- **iOS:** `sharedLoader` is read-only. Tests replace it through `TIImageLoaderRegistry+Testing.h`. `imageSizeForRequest:completion:` is required.
- **Both:** the compatibility defaults are gone.

## Consequences

- A smaller public surface, and no adapter contract to keep stable.
- The headers in `ios/LoaderAPI/include` are still public module headers, because SwiftPM's adapter target and the tests import them. They are documented as internal; nothing in Objective-C can enforce that.
- An app that wants a different loader has to fork. That is accepted: no one has asked.
- The default loader is still found with `NSClassFromString`, as 0003 decided. Referencing it directly would need the registry to move out of the seam target. Not done; it is a run-time check the example app exercises on every CI run.

More: `docs/audit/V2_SIMPLIFICATION_PLAN.md` (S1).
