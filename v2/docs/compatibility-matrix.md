# Native dependency compatibility matrix

Source of truth for pins: `scripts/native-versions.env`. Last verified 2026-11-16.

Legend: ✅ verified by building (and running, where noted) · 🟡 builds, needs more verification · 🔬 evaluation only · ❌ incompatible · — not applicable

## Production baseline (TurboImage 2.0.0-alpha.0)

| Component | Pinned | Requires | Status |
|---|---|---|---|
| React Native | 0.88.1 | Node ≥ 22.11, New Architecture | ✅ example runs on iOS and Android |
| Nuke (SwiftPM) | 13.2.3 (`exact:`) | iOS 15, Swift tools 6.0 | ✅ standalone + in app via RN SPM |
| Nuke (CocoaPods) | 13.2.3, vendored xcframework | Same tag, built by `build-nuke-xcframework.sh` | ✅ example runs |
| Coil | 3.6.3 (`coil-core`, `coil-network-okhttp`) | **Kotlin ≥ 2.3** in the app (built with 2.4.10) | ✅ debug run; R8 release smoke test 7/7 |
| Kotlin (app) | 2.4.21 | — | ✅ |
| AGP | 9.2.1 (from RN) | Gradle 9.4.1, JDK 17 | ✅ |
| Android NDK | 27.1.12297006 | — | ✅ (16 KB page alignment set) |
| compileSdk / targetSdk / minSdk | 37 / 36 / 24 | — | ✅ |
| C++ standard | C++20 | Apple Clang (Xcode 27.2), NDK Clang, CMake ≥ 3.22 | ✅ |
| GoogleTest | 1.17.0 | — | ✅ 13/13 |
| Bun | 1.3.13, hoisted linker | — | ✅ |
| react-native-safe-area-context (example only) | 5.11.1 | — | ✅ |
| Xcode | 27.2 (local) | Swift tools ≥ 6.2 for Package.swift | ✅ |

## Cross-version matrix

| | RN 0.88.1 (Kotlin 2.2.0 default) | RN 0.88.1 + Kotlin 2.4.21 | RN 0.89.0-rc.1 (Kotlin 2.3.21, NDK 28.2) |
|---|---|---|---|
| Coil 3.6.3 | ❌ metadata 2.4 unreadable by 2.2. The library's Gradle check fails early with a fix-it message | ✅ | ✅ R8 release smoke test 7/7 with the template's Kotlin 2.3.21. This confirms Kotlin 2.3 reads Coil's 2.4 metadata |
| Android NDK | 27.1 ✅ | 27.1 ✅ | 28.2 ✅ (AGP auto-installs it) |
| iOS (CocoaPods, Release simulator) | — | ✅ | ✅ smoke test 7/7 |

RN 0.89 app-side changes, none of them in TurboImage itself:

- Apps must add `@react-native/community-cli-plugin` as a devDependency. `bundle` moved there, and release bundling fails without it.
- `DefaultReactActivityDelegate(activity, name, fabricEnabled)` is removed. The example now uses the two-argument form, which also works on 0.88.
- npm/Bun warn that `0.89.0-rc.1` doesn't satisfy the library's `react-native >=0.88.0` peer range (semver excludes prereleases). This is harmless.

Reproduce with `scripts/eval-rn-version.sh <version>`. CI job: `eval-rn-0-89`.

| | iOS 15.1 floor (RN default) | iOS 16.0 floor |
|---|---|---|
| Nuke 13.2.3 | ✅ | ✅ |
| Nuke 14.0.0-rc.1 | ❌ Nuke 14 requires iOS 16 | 🔬 standalone package builds with **no adapter changes** (`ImagePipeline.Configuration`, `ImageRequest.Options`, `imageID` and `ImageTask.image` are source-compatible). Not run in the app yet |

| iOS integration | CocoaPods | RN SwiftPM (0.88 preview) |
|---|---|---|
| Debug, simulator | ✅ runs | ✅ runs |
| Release, simulator | ✅ smoke test 7/7 | ✅ smoke test 7/7 |
| Device (arm64) | 🟡 not yet built | 🟡 not yet built |
| `use_frameworks! :linkage => :static` | 🟡 not yet built | — |

## Behaviour parity (adapter configuration)

See RFC §4.2. Things to re-verify on every Nuke or Coil bump:

- [ ] `imageID` (Nuke) and `memoryCacheKey`/`diskCacheKey` (Coil) still key both tiers.
- [ ] HTTP caching is still disabled (`withDataCache` sets `urlCache = nil`; `CacheStrategy.DEFAULT` semantics).
- [ ] Coil's `DeDupeConcurrentRequestStrategy` still exists. It is `@ExperimentalCoilApi`.
- [ ] Cancellation drops callbacks (`ImageTask.cancel` / `Disposable.dispose`).
- [ ] Error classification still holds. The smoke test's `cacheMiss` expects `notCached` (Nuke `dataMissingInCache`; Coil's synthetic 504).
- [ ] The R8 mapping keeps `com.turboimage.core.{ResolvedRequest,ResolveFailure,TurboImageCore}` (CI asserts this).
