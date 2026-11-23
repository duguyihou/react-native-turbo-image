# Native dependency compatibility matrix

Source of truth for pins: `scripts/native-versions.env`. Last verified 2026-11-16; rows that say 49/49 or 98/98 on 2026-11-19.

Legend: ✅ verified by building (and running, where noted) · 🟡 builds, needs more verification · 🔬 evaluation only · ❌ incompatible · — not applicable

Smoke results are recorded as passed/total of the suite when the row was verified. The suite has 49 scenarios today (RFC §8). The RN 0.89 results are from the hosted `v2-ci.yml` run on 3b08d09 (x86_64 Android emulator); the RN 0.88 results were also run locally (arm64 emulator, iOS 27.2 simulator), RN SwiftPM only locally.

## Production baseline (TurboImage 2.0.0-alpha.0)

| Component | Pinned | Requires | Status |
|---|---|---|---|
| React Native | 0.88.1 | Node ≥ 22.11, New Architecture | ✅ example runs on iOS and Android |
| Nuke (SwiftPM) | 14.0.0 (`exact:`) | iOS 16, tvOS 16, Swift tools 6.4 (Xcode 27) | ✅ standalone, iOS and tvOS simulator builds (2026-11-23). In an app via RN SPM: last run with 13.2.3 |
| Nuke (CocoaPods) | 14.0.0, vendored `Nuke.xcframework` and `NukeUI.xcframework` | Same tag, built by `build-nuke-xcframework.sh`; iOS and tvOS slices | ✅ example runs; smoke test 49/49 (2026-11-23) |
| react-native-tvos (tvOS) | 0.88.1-0 | tvOS 16.0 (15.1 when this row was verified, with Nuke 13.2.3); app from `@react-native-tvos/template-tv` 0.83.0-0, the newest published | 🟡 2026-11-18: the packed library builds into a Release app for the tvOS simulator and device SDKs (`test-packed-install.sh tvos`), and the SwiftPM package builds standalone for tvOS. Never run: no tvOS simulator runtime was installed. Android TV not tried |
| Coil | 3.6.3 (`coil-core`, `coil-network-okhttp`, `coil-network-cache-control`, `coil-gif`, `coil-svg`) | **Kotlin ≥ 2.3** in the app (built with 2.4.10) | ✅ debug run; R8 release smoke test 49/49 |
| Kotlin (app) | 2.4.21 | — | ✅ |
| AGP | 9.2.1 (from RN) | Gradle 9.4.1, JDK 17 | ✅ |
| Android NDK | 27.1.12297006 | — | ✅ (16 KB page alignment set) |
| compileSdk / targetSdk / minSdk | 37 / 36 / 24 | — | ✅ |
| C++ standard | C++20 | Apple Clang (Xcode 27.2), NDK Clang, CMake ≥ 3.22 | ✅ |
| GoogleTest | 1.17.0 | — | ✅ 98/98 on host (Apple Clang) and on the Android arm64 emulator |
| Bun | 1.3.13, hoisted linker | — | ✅ |
| react-native-safe-area-context (example only) | 5.11.1 | — | ✅ |
| Xcode | 27.2 (local) | Swift tools ≥ 6.2 for Package.swift | ✅ |
| blurhash / thumbhash (npm, devDependencies) | 2.0.5 / 0.1.1 | Reference implementations for the C++ goldens only | ✅ |

## Verification log

What has been built and run, and when. Moved here from RFC 0001 §9, which
recorded the first of these: the gate that released the pipeline work.

Verified locally on 2026-11-16 (Xcode 27.2, JDK 17, macOS 27). Test and
scenario counts are those of the suite when each row was verified: the smoke
suite had 7 scenarios, then 17, then 38, and has 49 now (RFC §8). Dated rows were
re-run that day. Rows that name CI are from the hosted run of `v2-ci.yml` on
3b08d09 (run 44453245980), whose Android emulator is x86_64.

| Check | Result |
|---|---|
| C++ core, 119 GoogleTests (host CMake, 2026-11-20; 118 of them also under ASan and UBSan that day) | ✅ pass |
| C++ core, 118 GoogleTests on the Android arm64 emulator (NDK 27.1, 16 KB pages, 2026-11-20) | ✅ pass |
| iOS device (`iphoneos`) Release build, CocoaPods and SwiftPM (unsigned) | ✅ compiles and links; not run (no device attached) |
| SwiftPM standalone, Nuke 13.2.3 | ✅ build |
| SwiftPM standalone, Nuke 14.0.0-rc.1 | ✅ build (no source changes) |
| SwiftPM standalone, Nuke 14.0.0, iOS and tvOS simulator (local, 2026-11-23) | ✅ build |
| Smoke test, iOS Release simulator (CocoaPods), Nuke 14.0.0 and the iOS 16.0 floor (local, 2026-11-23) | ✅ 49/49. Not re-run with Nuke 14: the RN SwiftPM app path, the RN 0.89 copy, device builds, the tvOS app |
| iOS animated images on the paths no event reports, by screenshots of a temporary screen (local, iOS simulator, 2026-11-23) | ✅ GIF, APNG and WebP play; so do a memory-cache hit, a view recycled while playing, a still replaced by an animation in one view, and the cross-fade into an animation. An animation replaced by a still stops. Two sizes of one GIF get one animation object. With Reduce Motion on, every one is a still |
| Nuke adapter tests, 45 in four suites (`bun run test:ios`, SwiftPM standalone, iOS simulator; local, 2026-11-23) | ✅ pass. They load real GIF, PNG and SVG files through the seam. Animated images: clearing or replacing the image stops an animation, a processed animation is a still, two sizes share one animation, changed bytes get a new one. Loading: decode bounds, the four failure codes, cancel, prefetch. Memory cache: read and write flags, one entry per size and per processing, eviction of every variant, the `memoryCacheKey` lookup. SVG: the vector is left alone by a decode bound and drawn at the requested size for a processor. Not covered: the disk and HTTP caches (the files are local), progress, headers |
| One native view recycled from an APNG into a still and then into a GIF (temporary screen with one image at a time, view pointer logged; local, 2026-11-23) | ✅ plays, is still (seven identical screenshots), plays |
| Packed install into a new RN 0.88.1 template app with its target raised to 16.0 (`test-packed-install.sh ios`, local, 2026-11-23) | ✅ loads an image |
| iOS example, CocoaPods, Debug simulator | ✅ build; all four policies render, the load event fires |
| iOS example, RN SwiftPM (`spm add --deintegrate`), Debug simulator | ✅ build; renders |
| Android example, debug, arm64 emulator | ✅ build; renders; `libturboimage.so` loads |
| Android example, release (R8), arm64 emulator | ✅ build; renders; JNI classes kept |
| Smoke test, iOS Release simulator (CocoaPods) | ✅ 49/49 (CI, 2026-11-19; local with the lifecycle in the core, 2026-11-20) |
| Smoke test, Android R8 release, arm64 emulator | ✅ 49/49 (2026-11-20, with the lifecycle in the core); also 49/49 on the x86_64 emulator (CI, 2026-11-19) |
| Smoke test, iOS Release simulator via RN SwiftPM | ✅ 49/49 (local, iOS 27.2 simulator, 2026-11-20). CI builds this path in Debug and does not run the suite on it |
| RN 0.89.0-rc.1 (Kotlin 2.3.21, NDK 28.2): smoke test on iOS and Android | ✅ 49/49 each (CI, 2026-11-19) |
| CI workflow (`v2-ci.yml`) on GitHub-hosted runners | ✅ every job passed on PR #454 (2026-11-18) |

## Cross-version matrix

| | RN 0.88.1 (Kotlin 2.2.0 default) | RN 0.88.1 + Kotlin 2.4.21 | RN 0.89.0-rc.1 (Kotlin 2.3.21, NDK 28.2) |
|---|---|---|---|
| Coil 3.6.3 | ❌ metadata 2.4 unreadable by 2.2. The library's Gradle check fails early with a fix-it message | ✅ | ✅ R8 release smoke test 49/49 with the template's Kotlin 2.3.21. This confirms Kotlin 2.3 reads Coil's 2.4 metadata |
| Android NDK | 27.1 ✅ | 27.1 ✅ | 28.2 ✅ (AGP auto-installs it) |
| iOS (CocoaPods, Release simulator) | — | ✅ | ✅ smoke test 49/49 |

RN 0.89 app-side changes, none of them in TurboImage itself:

- Apps must add `@react-native/community-cli-plugin` as a devDependency. `bundle` moved there, and release bundling fails without it.
- `DefaultReactActivityDelegate(activity, name, fabricEnabled)` is removed. The example now uses the two-argument form, which also works on 0.88.
- The library's `react-native` peer range is `*` since 2026-11-18, so a pre-release no longer raises a peer warning. The earlier `>=0.88.0` excluded every pre-release by semver's rules, and every react-native-tvos version is one (`0.88.1-0`), which made `npm install` fail outright for Apple TV apps.

Reproduce with `scripts/eval-rn-version.sh <version>`. CI job: `eval-rn-0-89`.

| | iOS 15.1 floor (RN default) | iOS 16.0 floor |
|---|---|---|
| Nuke 13.2.3 (pinned until 2026-11-23) | ✅ | ✅ |
| Nuke 14.0.0 (pinned) | ❌ Nuke 14 requires iOS 16 | ✅ no adapter changes needed to compile (`ImagePipeline.Configuration`, `ImageRequest.Options`, `imageID` and `ImageTask.image` are source-compatible). Since then the adapter plays animations with NukeUI's player (ADR 0012) |

| iOS integration | CocoaPods | RN SwiftPM (0.88 preview) |
|---|---|---|
| Debug, simulator | ✅ runs | ✅ runs |
| Release, simulator | ✅ smoke test 49/49 | ✅ smoke test 49/49 |
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
