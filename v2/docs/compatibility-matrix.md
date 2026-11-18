# Native dependency compatibility matrix

Source of truth for pins: `scripts/native-versions.env`. Last verified 2026-11-16; rows that say 38/38 or 90/90 on 2026-11-17.

Legend: ✅ verified by building (and running, where noted) · 🟡 builds, needs more verification · 🔬 evaluation only · ❌ incompatible · — not applicable

Smoke results are recorded as passed/total of the suite when the row was verified. "7/7" rows date from the 7-scenario suite and have not been re-run against today's 38 scenarios (RFC §8).

## Production baseline (TurboImage 2.0.0-alpha.0)

| Component | Pinned | Requires | Status |
|---|---|---|---|
| React Native | 0.88.1 | Node ≥ 22.11, New Architecture | ✅ example runs on iOS and Android |
| Nuke (SwiftPM) | 13.2.3 (`exact:`) | iOS 15, Swift tools 6.0 | ✅ standalone + in app via RN SPM |
| Nuke (CocoaPods) | 13.2.3, vendored xcframework | Same tag, built by `build-nuke-xcframework.sh`; iOS and tvOS slices | ✅ example runs |
| react-native-tvos (tvOS) | 0.88.1-0 | tvOS 15.1; app from `@react-native-tvos/template-tv` 0.83.0-0, the newest published | 🟡 2026-11-18: the packed library builds into a Release app for the tvOS simulator and device SDKs (`test-packed-install.sh tvos`), and the SwiftPM package builds standalone for tvOS. Never run: no tvOS simulator runtime was installed. Android TV not tried |
| Coil | 3.6.3 (`coil-core`, `coil-network-okhttp`, `coil-network-cache-control`, `coil-gif`, `coil-svg`) | **Kotlin ≥ 2.3** in the app (built with 2.4.10) | ✅ debug run; R8 release smoke test 38/38 |
| Kotlin (app) | 2.4.21 | — | ✅ |
| AGP | 9.2.1 (from RN) | Gradle 9.4.1, JDK 17 | ✅ |
| Android NDK | 27.1.12297006 | — | ✅ (16 KB page alignment set) |
| compileSdk / targetSdk / minSdk | 37 / 36 / 24 | — | ✅ |
| C++ standard | C++20 | Apple Clang (Xcode 27.2), NDK Clang, CMake ≥ 3.22 | ✅ |
| GoogleTest | 1.17.0 | — | ✅ 90/90 on host (Apple Clang) and on the Android arm64 emulator |
| Bun | 1.3.13, hoisted linker | — | ✅ |
| react-native-safe-area-context (example only) | 5.11.1 | — | ✅ |
| Xcode | 27.2 (local) | Swift tools ≥ 6.2 for Package.swift | ✅ |
| blurhash / thumbhash (npm, devDependencies) | 2.0.5 / 0.1.1 | Reference implementations for the C++ goldens only | ✅ |

## Cross-version matrix

| | RN 0.88.1 (Kotlin 2.2.0 default) | RN 0.88.1 + Kotlin 2.4.21 | RN 0.89.0-rc.1 (Kotlin 2.3.21, NDK 28.2) |
|---|---|---|---|
| Coil 3.6.3 | ❌ metadata 2.4 unreadable by 2.2. The library's Gradle check fails early with a fix-it message | ✅ | ✅ R8 release smoke test 7/7 with the template's Kotlin 2.3.21. This confirms Kotlin 2.3 reads Coil's 2.4 metadata |
| Android NDK | 27.1 ✅ | 27.1 ✅ | 28.2 ✅ (AGP auto-installs it) |
| iOS (CocoaPods, Release simulator) | — | ✅ | ✅ smoke test 7/7 |

RN 0.89 app-side changes, none of them in TurboImage itself:

- Apps must add `@react-native/community-cli-plugin` as a devDependency. `bundle` moved there, and release bundling fails without it.
- `DefaultReactActivityDelegate(activity, name, fabricEnabled)` is removed. The example now uses the two-argument form, which also works on 0.88.
- The library's `react-native` peer range is `*` since 2026-11-18, so a pre-release no longer raises a peer warning. The earlier `>=0.88.0` excluded every pre-release by semver's rules, and every react-native-tvos version is one (`0.88.1-0`), which made `npm install` fail outright for Apple TV apps.

Reproduce with `scripts/eval-rn-version.sh <version>`. CI job: `eval-rn-0-89`.

| | iOS 15.1 floor (RN default) | iOS 16.0 floor |
|---|---|---|
| Nuke 13.2.3 | ✅ | ✅ |
| Nuke 14.0.0-rc.1 | ❌ Nuke 14 requires iOS 16 | 🔬 standalone package builds with **no adapter changes** (`ImagePipeline.Configuration`, `ImageRequest.Options`, `imageID` and `ImageTask.image` are source-compatible). Not run in the app yet |

| iOS integration | CocoaPods | RN SwiftPM (0.88 preview) |
|---|---|---|
| Debug, simulator | ✅ runs | ✅ runs |
| Release, simulator | ✅ smoke test 38/38 | ✅ smoke test 7/7 |
| Device (arm64) | 🟡 compiles and links (unsigned Release); not run | 🟡 compiles and links (unsigned Release); not run |
| `use_frameworks! :linkage => :static` | 🟡 not yet built | — |

## Behaviour parity (adapter configuration)

See RFC §4.2. Things to re-verify on every Nuke or Coil bump:

- [ ] `imageID` (Nuke) and `memoryCacheKey`/`diskCacheKey` (Coil) still key both tiers.
- [ ] HTTP caching is still disabled for keyed requests (`withDataCache` sets `urlCache = nil`; `CacheStrategy.DEFAULT` semantics).
- [ ] `urlCache` still obeys `Cache-Control` on both platforms (RFC §4.2a). Coil's `CacheControlCacheStrategy` is `@ExperimentalCoilApi`; the smoke scenarios `urlCache*` assert the requests the fixture server received.
- [ ] Decode-time downscaling still holds (RFC §4.5c): the smoke scenarios `downscaled` and `fullSize`.
- [ ] Coil's `DeDupeConcurrentRequestStrategy` still exists. It is `@ExperimentalCoilApi`.
- [ ] Cancellation drops callbacks (`ImageTask.cancel` / `Disposable.dispose`).
- [ ] Error classification still holds. The smoke test's `cacheMiss` expects `notCached` (Nuke `dataMissingInCache`; Coil's synthetic 504).
- [ ] The R8 mapping keeps `com.turboimage.core.{ResolvedRequest,ResolveFailure,PlaceholderPixels,TurboImageCore}` (CI asserts this).
