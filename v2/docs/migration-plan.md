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
| `placeholder` (blurhash/thumbhash/memoryCacheKey) | Decoders in **core C++** | ✅ blurhash and thumbhash done (byte-exact vs. references, kept on failure). `memoryCacheKey` waits for the cache TurboModule |
| `resize`, `blur`, `monochrome`, `tint`, `borderRadius` processors | Core describes processors; adapters map them to Nuke `ImageProcessors` / Coil `Transformation` | The processor list becomes part of the cache key in core |
| `enableLiveTextInteraction` (iOS) | iOS-only prop | |
| `prefetch`, `dispose`, `clearMemoryCache`, `clearDiskCache` | New **TurboModule** | Codegen `type: "all"` |
| GIF, APNG, SVG | Adapter decoders | Re-evaluate Gifu/APNGKit vs Nuke 13 built-ins; Coil `coil-gif`/`coil-svg` |
| Local assets / `require()` sources | Core scheme handling | Out of scope in the skeleton (`UnsupportedScheme`) |
| `headers` | Seam field | Needs RFC open question 5 settled |

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
