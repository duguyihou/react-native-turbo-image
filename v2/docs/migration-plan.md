# Migration plan: TurboImage 1.x → 2.0

## Starting point (1.24.3 on `main`)

- Single-package repo using Yarn 3. The example uses RN 0.73.6.
- Supports both the Old and New Architecture (`RCT_NEW_ARCH_ENABLED` branches in the podspec).
- iOS: Swift view manager, Nuke **12.8.0** vendored as a prebuilt xcframework (all Apple platforms), plus Gifu, APNGKit and CoreSVG.
- Android: Coil (2.x API), Kotlin view manager, ProgressInterceptor, blurhash/thumbhash decoders, APNG decoder.
- There's no shared code: cache-key and policy semantics are implemented twice, and 1.x policies (`urlCache` / `dataCache` / `memory`) already behave differently per platform.

## Principles

1. **The gate first.** No pipeline features until both platforms build the minimal example. ✅ met (RFC §9).
2. **Port behaviour, not code.** Each 1.x feature comes back by extending the core contract and then both adapters in the same PR, with GoogleTest coverage for the semantics.
3. **1.x stays releasable on `main`** until 2.0.0 ships. Fixes keep landing there.

## Phases

### Phase 0: walking skeleton (this branch)
Done: the `v2/` monorepo, the C++ core with the cache matrix, the Fabric
component (`source`, `cachePolicy`, `resizeMode`, `onLoad`, `onError`; the events were later renamed to 1.x's set), the
Nuke 13.2.3 and Coil 3.6.3 adapters, SwiftPM + CocoaPods + Gradle + CMake
builds, and the CI matrix.

### Phase 1: CI green and lifecycle hardening
- [ ] Run `v2-ci.yml` on GitHub-hosted runners and fix any differences from the local runs (runner Xcode version, NDK install, emulator).
- [x] Emulator and simulator smoke tests (`scripts/smoke-{ios,android}.sh`, 7 deterministic scenarios, release builds).
- [x] RFC open questions 1–3 resolved (Coil view and Activity lifecycle, deterministic `cacheOnly`).
- [x] Cross-platform `onFailure.code` taxonomy (RFC §4.4).
- [x] RN 0.89.0-rc.1 evaluation, scripted (`scripts/eval-rn-version.sh`) and run in CI (non-blocking).
- [x] iOS Release through RN SwiftPM verified by the smoke test.
- [x] Smoke scripts refuse stale build artifacts (`scripts/assert-fresh-build.sh`).

### Phase 2: pipeline parity with 1.x (ordered by usage)
| 1.x feature | 2.0 home | Notes |
|---|---|---|
| `cachePolicy` `urlCache`/`dataCache` | JS compatibility shim | ✅ both map to `'default'`, with development warnings; `urlCache` no longer honours HTTP headers (RFC §4.4b) |
| `resizeMode` default, `showPlaceholderOnFailure`, `fadeDuration`, `rounded` | Native props + JS | ✅ 1.x defaults kept (RFC §4.4b) |
| `cacheKey` | ✅ done | |
| `onStart`/`onProgress`/`onSuccess`/`onFailure`/`onCompletion` | Codegen events + seam callbacks | ✅ done, with 1.x names and payloads, plus `onFailure.code` and `onCompletion {state:'cancelled'}` (RFC §4.4a) |
| `placeholder` (blurhash/thumbhash/memoryCacheKey) | Decoders in **core C++** | ✅ done. Blurhash and thumbhash are byte-exact vs. the references; `memoryCacheKey` is a memory lookup via the seam |
| `resize`, `blur`, `monochrome`, `tint` processors | **Core C++** pixel ops; adapters attach one opaque step keyed by the core's `processorKey` | ✅ done (RFC §4.5a). Variants are separate memory entries over one disk original; `dispose` evicts all of them. 1.x's `borderRadius` processor never existed, and `rounded`'s circle crop is replaced by the clipping container |
| `enableLiveTextInteraction` (iOS) | iOS-only prop; Swift target `TurboImageLiveText` behind the ObjC `TILiveTextInteraction` seam | ✅ done (RFC §4.4b). One interaction per view (1.x stacked one per load); toggling off detaches at once. Visual Look Up needs iOS 17 |
| `indicator` (activity spinner while loading) | JS: `<ActivityIndicator>` over the native view, driven by `onStart`/`onCompletion` | ✅ done (RFC §4.4b). No native code. Appears only after 150 ms, so cache hits never flash it. Hidden when a `placeholder` is given (1.x Android's rule) |
| `allowHardware` (Android) | Not yet placed | Coil 3 still has `allowHardware`; processed loads already use software bitmaps |
| `isProgressiveImageRenderingEnabled` (iOS) | Not yet placed | Nuke 13 progressive decoding; Coil has no equivalent |
| `prefetch`, `dispose`, `clearMemoryCache`, `clearDiskCache` | New **TurboModule** | ✅ done (RFC §4.4c). `prefetch` now resolves `false` if any source fails; `dispose` actually works now (1.x never implemented it) |
| GIF, APNG, SVG | Adapter decoders, chosen by content | ✅ done (RFC §4.5b). ImageIO on iOS (drops Gifu and APNGKit), `coil-gif` + LINE `apng-drawable` on Android. SVG keeps 1.x's private CoreSVG on iOS by decision; `coil-svg` on Android. `format` is ignored |
| Video thumbnails (1.x Android `coil-video`) | Not yet placed | Missing from this plan until now. iOS 1.x had no equivalent |
| Local assets / `require()` sources | Core scheme handling | ✅ done (RFC §4.1). `require()` is new in 2.0 (1.x only took `{ uri }`); `file://`, `content://`, `android.resource://` are explicit now (1.x loaded them by accident). Local sources skip the disk tier and load under `cacheOnly` |
| `headers` | Core-validated seam field | ✅ done (RFC §4.1). Per-source, as in 1.x; not part of the cache key or the coalescing identity; CR/LF/NUL and non-token names are rejected (`invalidRequest`). App-wide hook (cookies) is a TODO |

### Phase 3: promote `v2/` to the repository root
1. Tag the final 1.x release and create a `1.x` maintenance branch.
2. On `main`: `git rm` the 1.x `ios/`, `android/`, `src/`, `example/`, Yarn config and `ci.yml`, then `git mv v2/* .` (keeping history for moved files).
3. Update `package.json` `repository.directory`, the workflow `working-directory` values and the docs paths.

### Phase 4: release
- `2.0.0-beta.N` on npm under the `next` tag. The tarball includes `ios/vendor/Nuke.xcframework`, built in CI from the pinned tag. A `prepack` hook should fail if the vendored version doesn't match.
- Publish a migration guide for app developers:
  - Requirements: New Architecture, RN ≥ 0.88, **Kotlin ≥ 2.3**, iOS 15.1.
  - Prop renames and the `cachePolicy` mapping.
  - The pod name changes from `react-native-turbo-image` to `TurboImage`. Autolinking handles this, but apps that reference the pod name directly need updating.
  - SwiftPM opt-in instructions (`npx react-native spm`).
- 2.0.0 once Phase 2 parity and both iOS integration paths are green in CI.

## Breaking changes for apps (draft)

- Old Architecture is no longer supported.
- Requires RN ≥ 0.88 and **Kotlin ≥ 2.3** (Coil 3.6.3).
- tvOS support is dropped until requested (1.x listed it in the podspec).
- `cachePolicy` values are renamed (with a shim during 2.x).
- HTTP `Cache-Control` headers are ignored on both platforms. In 1.x, iOS `urlCache` respected them.
- `onFailure` gains `code`. `onCompletion` can now report `state: 'cancelled'`.
- `indicator` appears only for loads that take longer than 150 ms, and is never shown together with a `placeholder` (1.x iOS showed whichever prop was set last).
- `source` may be a `require()` number. TypeScript code that reads `.uri` off `TurboImageProps['source']` must narrow it first.
- Local sources (`file://`, `content://`, `android.resource://`) are never copied into the disk cache, and `cacheOnly` does not block them.
- `format` is ignored: formats are detected from the bytes. Gifu and APNGKit are no longer dependencies.
- SVG on iOS still uses Apple's private CoreSVG framework, as in 1.x. Apps should know this is private-API use that App Review could flag.
- Processors on an animated image now produce a static image on iOS too (1.x iOS ignored the processors and animated the raw data).
- On iOS, animations larger than 64 MB decoded show only their first frame.
- On Android, image requests now send a descriptive `User-Agent` (`<App>/<version> TurboImage/<version> (Android <release>)`) instead of OkHttp's default.
- A `source.headers` entry with CR/LF/NUL in its value or a non-token name now fails the load with `invalidRequest` instead of being sent.
- Android no longer inherits React Native's shared `OkHttpClient`, so cookies set through RN's networking are not sent with image requests.
- `TurboImage.prefetch` resolves `false` when any source fails (1.x always resolved `true`).
- `blur`, `monochrome` and `tint` are now one cross-platform implementation, so results differ slightly from 1.x on both platforms. `blur` is σ in pixels of the (resized) image. On Android it now applies to the original-size decode, not the view-size one, so the same value looks weaker on large photos; pair it with `resize`. A `monochrome` colour's alpha is now its intensity.
