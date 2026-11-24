# TurboImage 2.0 architecture

The short version. Start here; the detail is elsewhere:

- **Why a thing is the way it is:** one record per decision in [`adr/`](adr/README.md).
- **Exactly how a feature behaves** (cache policies, events, placeholders, processors, formats, decode size): [RFC 0001](rfc/0001-turbo-image-2-native-toolchain.md), which the source comments cite by section number.

## The parts

```
 JS   <TurboImage …props>                      TurboImage.prefetch / dispose / clear…
        │ Codegen view spec                       │ Codegen TurboModule spec
 ───────┼─────────────────────────────────────────┼──────────────────────────────
        ▼                                         ▼
 View   TurboImageComponentView (ObjC++)        TurboImageModule (ObjC++ / Kotlin)
        TurboImageView (Kotlin)                   │
        │        │                                │
        │        │ what happened                  │
        │        ▼                                │
 Core   │   ViewLifecycle ── effects ──▶ view     │
 (C++)  │ props                                   │ sources
        ▼                                         ▼
        resolveRequest() ─────────── ResolvedRequest ───────────┐
        decodePlaceholder()   processImage()   ProgressThrottle  │
 ───────────────────────────────────────────────────────────────┼──────────────
 Seam   TIImageLoading (plain ObjC)        ImageLoaderAdapter (Kotlin)
        │                                   │
 Loader NukeImageLoader ── Nuke            CoilImageLoaderAdapter ── Coil
```

| Part | Where | What it owns |
|---|---|---|
| JS component | `src/index.tsx` | 1.x prop compatibility, `require()` sources, header normalisation, `rounded` as a style, and the `indicator` spinner and its container. No loading logic. |
| Codegen specs | `src/TurboImageViewNativeComponent.ts`, `src/NativeTurboImageModule.ts` | The contract between JS and the two native views and modules. |
| Core | `cpp/` | Every decision that must be the same on both platforms. See below. |
| Views | `ios/Fabric/TurboImageComponentView.mm`, `android/…/TurboImageView.kt` | Props in, events out, the image on screen. They carry out what the core decides. |
| Cache module | `ios/Fabric/TurboImageModule.mm`, `android/…/TurboImageModule.kt` | `prefetch`, `dispose`, `clearMemoryCache`, `clearDiskCache`, through the same core resolution and the same loader as the views. |
| Seams | `ios/LoaderAPI/include/`, `android/…/loader/ImageLoaderAdapter.kt` | The only contract between a view and an image loader. Internal: apps cannot replace the loader ([ADR 0014](adr/0014-the-loader-seam-is-internal.md)). |
| Adapters | `ios/Nuke/`, `android/…/loader/Coil*.kt` | Translating a resolved request into Nuke or Coil calls. The only code that names either library. |

## What the core decides

The core is standard-library C++20: pure functions on value types, no I/O, no
platform headers. It is compiled into both platforms from one source tree.

| Header (`cpp/include/turboimage/`) | Decides |
|---|---|
| `ImageRequest.h` | What a request means: validation, the cache key, which cache tiers a policy may read and write, how large to decode, the error codes JS sees. |
| `ViewLifecycle.h` | What a view shows and which load events JS sees, in every order of prop changes, loader callbacks, placeholder decodes and view reuse. Each step returns the effects the view must carry out. |
| `Processing.h` | `resize`, `blur`, `monochrome`, `tint`, as integer arithmetic on RGBA, and the key that names a processed variant. |
| `Placeholder.h` | Blurhash and thumbhash decoding, byte for byte the same everywhere. |
| `Progress.h` | How often a download reports progress. |

A view never interprets a prop that affects loading. It gathers the props
into the core's `ImageRequest` and starts a load when that value changes; it
hands the request to `resolveRequest()` and gets a `ResolvedRequest`; it
tells `ViewLifecycle` what happened and gets effects. An adapter never makes a policy decision. It
translates a `ResolvedRequest` field by field.

## Rules

The source comments cite these by number ("RFC rule 3").

1. **Loaders sit behind an internal seam.** Nuke and Coil are reached through `TIImageLoading` and `ImageLoaderAdapter`, and no loader type appears in the views or the JS API. The seam is structure, not an extension point: apps cannot replace the loader ([ADR 0014](adr/0014-the-loader-seam-is-internal.md)); tests can.
2. **The C++ core is the single owner of request semantics**: validation, cache keys, the cache-policy matrix, decode size. Adapters translate a `ResolvedRequest` and decide nothing.
3. **Both platforms behave the same.** Where the loaders differ (cache tiers, progress cadence, placeholder lifetime, error codes), the difference is closed in the core or in the adapters, not left to JS.
4. **One copy of shared logic.** The C++ in `cpp/` is compiled into both platforms from one source tree; nothing is ported or copied per platform.
5. **No Swift/C++ interop.** Swift targets hold no C-family sources and never import C++; ObjC++ sits between them.
6. **SwiftPM and CocoaPods build the same thing**: the same sources, flags, language modes and Nuke version. Apps use CocoaPods; `Package.swift` builds the same native layers without an app, for the adapter tests and tvOS ([ADR 0015](adr/0015-cocoapods-only-for-apps.md)).
7. **Every production dependency is pinned**, in one place (`scripts/native-versions.env`), and CI fails when a manifest disagrees.
8. **Pre-releases are evaluated apart from production**, in their own CI jobs, and are never a production dependency.

## The two seams are not the same shape

Both seams take a resolved request and report success or failure once, on the
main thread, and never after cancel. They differ in who puts the image on
screen:

| | iOS (`TIImageLoading`) | Android (`ImageLoaderAdapter`) |
|---|---|---|
| The adapter is given | The request, with the decode size in pixels | The request and the `ImageView` |
| Success delivers | A `UIImage` and, for an animated image, an opaque animation. The view cross-fades and hands both back to the adapter, which plays the animation in the image view it supplied ([ADR 0012](adr/0012-nuke-plays-animations-on-ios.md)) | The image's size; the adapter has already shown and cross-faded it |
| The decode size comes from | The view's bounds, read by the view | The view's laid-out size, awaited by the adapter |

This is deliberate; [ADR 0004](adr/0004-android-adapter-displays-the-image.md)
says why. The consequence to keep in mind: on Android a loader that does not
honour cancel can paint a stale image without the view's say, so the Android
adapter's cancel contract carries more weight than the iOS one.

## Threading

- **Core:** thread-safe and reentrant; results own their data.
- **Views and seams:** main thread. A load completes exactly once on the main thread, or never if it was cancelled first.
- **Off the main thread:** placeholder decoding and image processing (pure core calls on a background queue), and everything inside Nuke and Coil.

## Where the mirrored values are checked

Kotlin and plain ObjC cannot include the C++ definitions, so they repeat the
core's enum values. `android/src/main/cpp/TurboImageJni.cpp` and
`ios/Fabric/TurboImageComponentView.mm` hold `static_assert`s that fail the
build when the core's side changes alone.

## How it is verified

| What | How |
|---|---|
| Core decisions | GoogleTest (`bun run test:core`), on GCC, Clang, Apple Clang and the Android emulator. The lifecycle tests walk every order of events to a fixed depth. |
| JS component | Jest (`bun run test`), with the native view and module mocked. |
| Both platforms end to end | The smoke suite in `apps/example/App.tsx`: release builds, cold caches, a local fixture server (`scripts/smoke-ios.sh`, `scripts/smoke-android.sh`). |
| Packaging | `scripts/check-pack.sh`, `scripts/test-packed-install.sh`. |

The smoke suite observes events, not pixels. What a placeholder, a border or
a cross-fade looks like is checked by eye.
