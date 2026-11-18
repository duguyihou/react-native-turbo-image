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
- [x] Emulator and simulator smoke tests (`scripts/smoke-{ios,android}.sh`, 7 deterministic scenarios at the time, 38 now, release builds).
- [x] RFC open questions 1–3 resolved (Coil view and Activity lifecycle, deterministic `cacheOnly`).
- [x] Cross-platform `onFailure.code` taxonomy (RFC §4.4).
- [x] RN 0.89.0-rc.1 evaluation, scripted (`scripts/eval-rn-version.sh`) and run in CI (non-blocking).
- [x] iOS Release through RN SwiftPM verified by the smoke test.
- [x] Smoke scripts refuse stale build artifacts (`scripts/assert-fresh-build.sh`).

### Phase 2: pipeline parity with 1.x (ordered by usage)
| 1.x feature | 2.0 home | Notes |
|---|---|---|
| `cachePolicy` `urlCache`/`dataCache` | `urlCache`: a core policy backed by an HTTP cache on both platforms. `dataCache`: JS compatibility shim | ✅ done. `urlCache` honours `Cache-Control` (freshness, revalidation, `no-store`), now on Android too; its disk store is separate from the keyed one (RFC §4.2a). `dataCache` maps to `'default'` with a development warning (RFC §4.4b) |
| `resizeMode` default, `showPlaceholderOnFailure`, `fadeDuration`, `rounded` | Native props + JS | ✅ 1.x defaults kept, except `fadeDuration`: 300 ms on both platforms (1.x Android: 100 ms), and it now also applies over a placeholder (RFC §4.4b) |
| `cacheKey` | ✅ done | |
| `onStart`/`onProgress`/`onSuccess`/`onFailure`/`onCompletion` | Codegen events + seam callbacks | ✅ done, with 1.x names and payloads, plus `onFailure.code` and `onCompletion {state:'cancelled'}` (RFC §4.4a) |
| `placeholder` (blurhash/thumbhash/memoryCacheKey) | Decoders in **core C++** | ✅ done. Blurhash and thumbhash are byte-exact vs. the references; `memoryCacheKey` is a memory lookup via the seam |
| `resize`, `blur`, `monochrome`, `tint` processors | **Core C++** pixel ops; adapters attach one opaque step keyed by the core's `processorKey` | ✅ done (RFC §4.5a). Variants are separate memory entries over one disk original; `dispose` evicts all of them. 1.x's `borderRadius` processor never existed, and `rounded`'s circle crop is replaced by the clipping container |
| `enableLiveTextInteraction` (iOS) | iOS-only prop; Swift target `TurboImageLiveText` behind the ObjC `TILiveTextInteraction` seam | ✅ done (RFC §4.4b). One interaction per view (1.x stacked one per load); toggling off detaches at once. Visual Look Up needs iOS 17 |
| `indicator` (activity spinner while loading) | JS: `<ActivityIndicator>` over the native view, driven by `onStart`/`onCompletion` | ✅ done (RFC §4.4b). No native code. Appears only after 150 ms, so cache hits never flash it. Hidden when a `placeholder` is given (1.x Android's rule) |
| `allowHardware` (Android) | Android-only native prop; a display option on the loader seam, not part of the request | ✅ done. Checked once by log: `HARDWARE` by default, `ARGB_8888` with `allowHardware={false}` |
| `isProgressiveImageRenderingEnabled` (iOS) | Accepted and ignored | ✅ nothing to port: 1.x never enabled progressive decoding in its Nuke pipeline (off by default in Nuke 12.8.0), so the prop had no effect. Real progressive rendering would be a new, iOS-only feature (Coil has none) |
| `prefetch`, `dispose`, `clearMemoryCache`, `clearDiskCache` | New **TurboModule** | ✅ done (RFC §4.4c). `prefetch` now resolves `false` if any source fails; `dispose` actually works now (1.x never implemented it) |
| GIF, APNG, SVG | Adapter decoders, chosen by content | ✅ done (RFC §4.5b). ImageIO on iOS (drops Gifu and APNGKit), `coil-gif` + LINE `apng-drawable` on Android. SVG keeps 1.x's private CoreSVG on iOS by decision; `coil-svg` on Android. `format` is ignored |
| Video thumbnails (1.x Android `coil-video`) | Not ported | ✅ nothing to port: 1.x declared the dependency but never registered `VideoFrameDecoder`, so it never worked |
| Local assets / `require()` sources | Core scheme handling | ✅ done (RFC §4.1). `require()` is new in 2.0 (1.x only took `{ uri }`); `file://`, `content://`, `android.resource://` are explicit now (1.x loaded them by accident). Local sources skip the disk tier and load under `cacheOnly` |
| `headers` | Core-validated seam field | ✅ done (RFC §4.1). Per-source, as in 1.x; not part of the cache key or the coalescing identity; CR/LF/NUL and non-token names are rejected (`invalidRequest`). App-wide hook (cookies) is a TODO |
| — (new in 2.0) `recyclingKey` | View-level prop on both platforms; not part of the request | ✅ done (RFC §4.4d). The previous image now stays up while a new source loads; a changed key blanks the view first. The smoke suite passes with it, but nothing yet checks what is on screen during the second load |
| — (new in 2.0) `allowDownscaling` | Core decides the decode target; adapters downsample while decoding | ✅ done (RFC §4.5c). On by default: images are decoded no larger than the view (or the `resize` width). The disk keeps the original |

**Phase 2 status: every 1.x prop, event, static method and exported type has a 2.0 home.** The 1.x type names (`Start`, `Success`, `ResizeMode`, …) are exported as aliases. What remains before Phase 3 is hardening, tracked in `SESSION.md`: Android SVG at full size, and the first run of `v2-ci.yml` on hosted runners (Phase 1).

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
- `cachePolicy` `dataCache` is renamed `default` (with a shim during 2.x).
- HTTP `Cache-Control` headers are ignored except under `cachePolicy="urlCache"`, which honours them on both platforms (1.x: iOS only). What `urlCache` stores on disk is not visible to `cacheOnly`, and the reverse.
- Images are decoded no larger than their view by default, and `onSuccess` reports that decoded size, not the source's. A view that is zoomed, or grows after the image loaded, needs `allowDownscaling={false}`.
- `onFailure` gains `code`. `onCompletion` can now report `state: 'cancelled'`.
- When `source` (or a processor prop) changes, the previous image stays on screen until the new one has loaded; 1.x blanked the view. Lists that reuse views (FlashList) must pass a `recyclingKey`, such as the row's id, or a reused row briefly shows the previous row's image.
- `fadeDuration` defaults to 300 ms on Android too (1.x Android: 100 ms). Set `fadeDuration={100}` to keep the old timing.
- The fade now runs when a placeholder is set, cross-fading from the placeholder to the image. 1.x forced it to 0 in that case; set `fadeDuration={0}` to keep that.
- Passing more than one placeholder kind throws only in development builds; in release builds native picks one. 1.x threw in every build.
- `showPlaceholderOnFailure` without a `placeholder` is a no-op. 1.x threw.
- `isProgressiveImageRenderingEnabled` is ignored (it had no effect in 1.x either).
- `ref` gives the image view itself unless `rounded` or `indicator` is set, in which case it gives the container around it. 1.x always gave the container. Both are the view that carries `style`, so measuring is unaffected.
- Other `View` props (`testID`, accessibility props, `onLayout`) go to the image view, as in 1.x. With `rounded` or `indicator` that is the view inside the container.
- Switching `rounded` or `indicator` on or off for a mounted image adds or removes the container, which remounts the image view and restarts its load. 1.x always had the container.
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
