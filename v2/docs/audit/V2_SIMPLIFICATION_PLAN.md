# TurboImage v2: simplification plan

Companion to [`V2_ARCHITECTURE_AUDIT.md`](V2_ARCHITECTURE_AUDIT.md). The audit
holds the evidence; this document holds the decisions. `pkg/` stands for
`v2/packages/react-native-turbo-image/`.

Priorities:

- **P0:** critical correctness or architecture. **None found.**
- **P1:** significant complexity or maintenance cost.
- **P2:** minor.
- **P3:** speculative; usually defer.

Effort: **S** is under a day, **M** a few days, **L** a week or more.

**Timing matters.** 2.0 is an unpublished alpha (`2.0.0-alpha.0`). Every
removal below is cheapest *now*: once 2.0.0 ships, each public prop and
extension point is a five-year compatibility commitment.

## Summary

| ID | P | Action | Item | Effort |
|---|---|---|---|---|
| S1 | P1 | Simplify (**done**, 2026-11-25; the `NSClassFromString` lookup was kept, see ADR 0014) | Make the loader seam internal; drop runtime lookup and adapter-compatibility defaults | M |
| S2 | P1 | Simplify (**done**, 2026-11-25) | CocoaPods-only for apps in 2.0; keep `Package.swift` standalone for tests | S |
| S3 | P1 | Process | Scope freeze until 2.0.0, with an admission rule for new props | S |
| S4 | P1 | Keep, relocate | Move the TLA+ lifecycle model into the repository | S |
| S5 | P1 | Measure | iOS benchmark parity before quoting iOS performance | M |
| S6 | P2 | Simplify (**done**, 2026-11-25) | `prefetch`: drop `resize` / `'original'`; prefetch is disk-only | S |
| S7 | P2 | Defer (remove from 2.0) (**done**, 2026-11-25) | Source sets (`source={[...]}`) | M |
| S8 | P2 | Defer (**done**, 2026-11-25) | tvOS: label experimental, invest nothing further | S |
| S9 | P2 | Fixed | iOS: re-apply the placeholder when only `placeholder.uri` changes | S |
| S10 | P2 | Fixed | JNI `static_assert` for `ResizeMode::ScaleDown` | S |
| S11 | P2 | Verify (**skipped**, 2026-11-25: unlikely, and 1.x vendored Nuke the same way; kept as a known risk) | Duplicate `Nuke` module when the app also links Nuke | S |
| S12 | P3 | Measure, then keep or remove | `loadEventMask` | S |
| S13 | P3 | Simplify (**done**, 2026-11-25) | Android: skip animated images in upgrades, as iOS does | S |
| S14 | P3 | Document (**done**, 2026-11-25) | A written scope rule for the C++ core | S |
| S15 | P3 | Deprecate in 2.x, remove in 3.0 (**deprecated**, 2026-11-25) | `rounded`, `indicator`, `dataCache`, `format`, `isProgressiveImageRenderingEnabled`, `placeholder.memoryCacheKey` | S |

---

## A. Keep

These are correct as designed. Do not change them.

| Component | Why it stays |
|---|---|
| C++ `resolveRequest`, cache-policy matrix, `canonicalCacheKey`, header validation | One owner of request meaning. 1.x drifted without it (ADR 0001) |
| C++ `ViewLifecycle` effect machine | Ordering bugs are the main bug class. One exhaustively tested copy (ADR 0010) |
| C++ `Processing`, `Placeholder` | Identical pixels on both platforms; no Coil 3 transformation library |
| `DecodeSize` + `allowDownscaling` default + silent upgrades (ADR 0013) | Measured memory win. Upgrades make the default safe for growing views |
| One `ImageLoader` / `OkHttpClient` (Android) and one pipeline pair (iOS) per process, isolated from the host app | Correct ownership; no per-view allocation |
| Engines own fetch, coalescing, memory and disk caches, decode, downsampling, animation | Nothing re-implemented |
| Synchronous memory-hit completion (iOS), dispose-after-complete and `KeepCurrentImageTarget` (Android) | Prevent flicker and stale repaints in lists |
| `LaidOutSizeResolver`, `TurboImageBorders` + Java delegate, matrix placement workaround | Each closes a documented platform or React Native gap |
| `ProgressInterceptor` (gated), User-Agent interceptor, no cookie jar | Real, documented problems, small code |
| `urlCache` as a second store | 1.x compatibility; isolated in one branch per adapter |
| Fabric-only, Codegen-only, no custom ShadowNode | Minimum New Architecture integration |
| Vendored Nuke xcframework for CocoaPods; `native-versions.env` + check script | Nuke is not on trunk; the pins prevent manifest drift |
| Local fixture server + release-build smoke suite | Deterministic end-to-end coverage (ADR 0011) |
| `recyclingKey`, `onFailure.code`, `onCompletion {state:'cancelled'}` | Fix real 1.x gaps |

---

## B. Simplify

### S1 (P1, M): make the loader seam internal

- **Current:**
  - Architecture rule 1 promises apps a replaceable loader: `TIImageLoaderRegistry.sharedLoader` (settable) on iOS, and `TurboImageLoaders.set` on Android (`pkg/android/.../loader/TurboImageLoaders.kt:48`).
  - iOS finds Nuke by `NSClassFromString(@"TurboImageNukeLoader")` (`pkg/ios/LoaderAPI/TIImageLoaderRegistry.m:51`).
  - Both seams carry defaults "so an adapter written before X keeps compiling" (`ImageLoaderAdapter.kt:71`, `:87`; `@optional imageSizeForRequest:` in `TIImageLoading.h:128`).
- **Problem:**
  - It is speculative extensibility. There is one adapter per platform, and ADR 0004 says no second Android adapter is planned.
  - The Android seam is already Coil-shaped, so the replaceability promise is only half real.
  - It creates public API to keep stable, a runtime lookup that fails late, and two documented behaviour gaps (views keep a replaced loader's image view, `SESSION.md`).
- **Proposed:**
  - Keep the boundary as *internal* structure: on iOS for the Swift ↔ ObjC++ language split, on Android as the test fake's interface.
  - Remove `TurboImageLoaders.set` from the public surface; make it `internal`/`@VisibleForTesting` for `TurboImageViewTest`.
  - Make `sharedLoader` read-only publicly.
  - Delete the backward-compatibility defaults and make `imageSizeForRequest:` required.
  - Move the default-loader construction into the Fabric target, and reference `TurboImageNukeLoader` directly through the generated Swift header. Do this only if the hypothesis in audit §3.3 holds on both CocoaPods and SwiftPM; if it does not, keep `NSClassFromString`.
  - Reword rule 1 to: "Loader types do not appear in views or the JS API."
- **Benefit:** a smaller public contract, compile-time failure instead of run-time failure, and two `SESSION.md` gaps gone. ADR 0003's cycle disappears with the registry move.
- **Migration risk:** low. Unpublished alpha, no known external adapters. Supersede ADR 0003 with a new ADR.
- **Effort:** M.

### S2 (P1, S): CocoaPods-only for apps in 2.0

- **Current:**
  - `Package.swift` has two modes. In-app mode probes `../../../../xcframeworks` relative to a symlink in the app's build directory.
  - The `ios-spm-app` CI job converts the example to SwiftPM.
  - Rule 6 requires CocoaPods and SwiftPM to build identical things.
- **Problem:**
  - React Native's SwiftPM is preview, and the manifest depends on the app's build layout. `docs/spm-assessment.md` already concludes "Not yet [production-ready]".
  - A second app-integration path doubles iOS packaging support for a path the project itself does not recommend.
- **Proposed:**
  - Keep `Package.swift` in standalone mode only, where it hosts the Nuke adapter tests and the tvOS build.
  - Remove the `isInsideReactNativeApp` branch and the `ios-spm-app` job.
  - Re-add both when React Native ships the "V2" `.package(url:)` autolinking the assessment names as the flip condition.
- **Benefit:** about 60 lines of manifest and one CI job fewer, and no coupling to the app's build layout. Rule 6 shrinks to "same sources and Nuke tag for tests and pods".
- **Migration risk:** none. No published version offered SwiftPM.
- **Effort:** S.

### S6 (P2, S): `prefetch` is disk-only

- **Current:**
  - `PrefetchOptions.resize: number | 'original'` decodes into memory, keyed to match views with exactly that `resize` and no other processing.
  - `prefetchTarget` (`pkg/src/index.tsx:481`), `resolveForCache`'s resize branch (`TurboImageCore.kt:86`), the `destination` parameter in the TurboModule spec, and equivalent iOS code support it.
- **Problem:**
  - The API asks users to reason about memory-cache keys; its own doc comment needs 15 lines to say when it helps.
  - On iOS a layout-sized view can never hit it (`SESSION.md`).
  - A disk hit already completes within a frame or two (`src/index.tsx` comment on `INDICATOR_DELAY_MS`).
- **Proposed:**
  - `prefetch(sources, { cachePolicy? })` always stores to disk. Under `memoryOnly`, or for local files, where there is no disk tier, it decodes at full size, as today.
  - Drop `destination` and `resize` from the native spec.
- **Benefit:** one simple promise ("it will be on disk"), and less resolution logic on three layers.
- **Migration risk:** low. The option is new in 2.0 (commit `f557f02`).
- **Effort:** S.

### S13 (P3, S): Android skips animated images in upgrades

- **Current:** an upgrade on Android restarts an animated image (`TurboImageView.kt:574-578`, TODO). iOS never upgrades animations.
- **Proposed:** skip the upgrade when the shown drawable is `Animatable`. That check does not need Coil's types.
- **Benefit:** platform parity, and one TODO gone. **Risk:** none. **Effort:** S.

### S14 (P3, S): write down the core's scope

- **Current:** "Every decision that must be the same on both platforms" goes in the core (`architecture.md`), so geometry helpers have each gained a JNI entry point and a Kotlin wrapper.
- **Proposed:** add one paragraph to `architecture.md`. The core holds:
  - request meaning (validation, keys, tiers, decode target),
  - the view lifecycle,
  - pixel-exact algorithms.

  New pure helpers go in the core only if both views would otherwise duplicate more than trivial logic. Do not move existing helpers.
- **Benefit:** it stops the JNI surface growing by default. **Risk:** none. **Effort:** S.

---

## C. Remove

### S12 (P3, S): `loadEventMask`, unless measured

- **Current:** an internal Codegen prop. Both views check a bit before building each event. The commit `3aee9ca` says the gain is "Unmeasured".
- **Proposed:** run audit benchmark 4 (event-mask A/B). If JS-thread time on a 30-image cold screen does not improve measurably, remove the prop and the gating. If it does, keep it and record the number.
- **Risk:** none either way. **Effort:** S.

### S15 (P3, S): the 1.x compatibility surface, on a schedule

These items stay working through 2.x, warn in development (as `dataCache`
already does), and are removed in 3.0:

| Item | Why it goes | Replacement |
|---|---|---|
| `rounded` | It is `borderRadius: 9999` | `style={{ borderRadius: 9999 }}` |
| `indicator` | It forces a container that moves `ref`/`testID` and remounts on toggle (ADR 0009) | An app overlay driven by `onStart`/`onCompletion` |
| `cachePolicy="dataCache"` | Alias of `'default'` | `'default'` |
| `format`, `isProgressiveImageRenderingEnabled` | Ignored already | None |
| `placeholder.memoryCacheKey` | Largely covered by `placeholder={{ uri }}`. Keeping it needs the iOS variant-index lookup path and the Android key scan for placeholders | `placeholder={{ uri: thumbnailUri }}` |
| 1.x type aliases (`Start`, `Success`, …) | Names only | The `*Event` types |

---

## D. Defer

### S7 (P2, M): source sets, out of 2.0

- **Current:**
  - `source` may be an array of `{uri, width, height}` (expo-image's form).
  - The core has `chooseSource` and `largerSourceFor`. Both views track candidates.
  - Android defers the start to the first layout (`startWhenLaidOut`, `pendingStart`, `hasLayout`, `TurboImageView.kt:463`).
- **Problem:**
  - No recorded user demand.
  - It adds a pre-layout code path that exists only for this feature, and a state dimension the lifecycle model and both view test suites must cover.
  - Apps can choose a URL in JS from `onLayout` or `PixelRatio`, with no library support.
- **Proposed:** remove the array form, the `sources` Codegen prop, `chooseSource` and `largerSourceFor`, and the Android layout wait, before 2.0.0. Reintroduce it if users ask.
- **Benefit:** fewer view fields on both platforms, one Android startup path, and fewer smoke scenarios.
- **Migration risk:** low. New in 2.0. expo-image migrators pass a single source.
- **Effort:** M (code, tests and scenarios on both platforms).

### S8 (P2, S): tvOS

- **Current:** podspec and `Package.swift` declare tvOS 16, the xcframeworks ship tvOS slices, and CI builds for tvOS. It has never run on a device, and there is no smoke suite (`SESSION.md`).
- **Proposed:** keep it compiling, label it "experimental, community-supported" in the README, and add no further tvOS work.
- **Risk:** none. **Effort:** S.

### Not to build yet

These are not to be started before 2.0.0:

- Public loader replacement (see S1).
- In-app SwiftPM (see S2).
- `contentPosition` point offsets (TODO in `src/index.tsx`).
- A native indicator (TODO).
- A decoded-placeholder cache (already declined in `SESSION.md`).
- An Android cookie opt-in and a default-headers hook (TODOs).
- Progressive rendering.
- GPU or SIMD blur.
- Serving a larger cached variant to a smaller view on iOS.

Each needs an issue showing demand, plus a benchmark where performance is the motivation.

---

## Process and measurement

### S3 (P1, S): scope freeze until 2.0.0

- **Current:** 30 `feat` commits in 10 days on the branch. Each feature lands in both views, the core, the specs and the smoke suite.
- **Proposed:** until 2.0.0, accept only fixes, tests, measurements and the items in this plan. After 2.0.0, a new public prop or static needs all three of:
  1. a user-facing issue,
  2. a statement of which existing prop cannot do it,
  3. for performance features, a benchmark number.
- **Benefit:** it bounds the state space while the lifecycle model and the view tests catch up (`SESSION.md` lists placeholders, `recyclingKey` and progress as untested in the view tests).
- **Risk:** none. **Effort:** S.

### S4 (P1, S): the TLA+ model goes into the repository

- **Current:** `ViewLifecycle.tla` and its skill live in `/.claude/`, which is gitignored (`.gitignore:89`). Copies of mutation runs sit in `v2/tmp/`.
- **Problem:** the formal check for the most bug-prone component exists in one clone.
- **Proposed:**
  - Commit the model under `v2/verification/lifecycle/` with a README and the exact TLC command.
  - Optionally add a manual-dispatch CI job.
  - Keep the skill as a thin pointer to it.
- **Risk:** none. **Effort:** S.

### S5 (P1, M): iOS benchmark parity

- **Current:** `apps/bench` is Android-only. iOS performance is unmeasured.
- **Proposed:** add an iOS target with the `load` and `grid` scenarios, plus the fast-fling benchmark (audit §5.4, items 1-2). Quote no iOS performance claim until it exists.
- **Risk:** none. **Effort:** M.

---

## Fixes

| ID | Current | Fix | Effort |
|---|---|---|---|
| S9 (P2) | `TurboImageComponentView.mm:336-340` sets `_needsPlaceholder` for `blurhash`, `thumbhash` and `memoryCacheKey` changes, not for `placeholder.uri`. A uri-only change while loading leaves the old placeholder on iOS; Android re-applies it | Add `oldViewProps.placeholder.uri != newViewProps.placeholder.uri` to the comparison, plus an iOS view test | S |
| S10 (P2) | `TurboImageJni.cpp:47-50` asserts `ResizeMode` 0-3 only | Add `TI_ASSERT_ABI(turboimage::ResizeMode::ScaleDown, 4);` | S |
| S11 (P2) | [H] Two `Nuke` modules if the app links Nuke too | Build the example with Nuke as an app SwiftPM dependency, under static and dynamic linkage. Document the outcome or fix the packaging | S |

---

## Proposed architecture

It is the current architecture, narrowed. Nothing is rewritten.

```
 JS    <TurboImage>  (props → Codegen, 1.x shims on a removal schedule)
       TurboImage.prefetch / getSize / dispose / clear* / configureCache
 ──────────┬────────────────────────────────────────────┬───────────────
 View      │ TurboImageComponentView (ObjC++)            │ TurboImageModule
           │ TurboImageView (Kotlin)                     │
           ▼                                             ▼
 Core      resolveRequest · ViewLifecycle · Processing · Placeholder   (C++20, one tree)
 ──────────┬─────────────────────────────────────────────────────────────
 Internal  │ iOS: ObjC protocol (language boundary only, not public)
 boundary  │ Android: Kotlin interface (test fake only, not public)
           ▼
 Engine    NukeImageLoader → Nuke + NukeUI      CoilImageLoaderAdapter → Coil 3
           one isolated pipeline per process     one isolated ImageLoader per process
```

What changes against today:

- **No public loader replacement.** No `NSClassFromString`; no compatibility defaults.
- **No source sets.** The views have one candidate and one start path.
- **`prefetch` is disk-only.**
- **Apps integrate through CocoaPods only.** SwiftPM stays for tests.
- **Fixes:** S9 and S10.
- **The model check is in the repository.**

## Migration strategy

Ordered so that each step leaves CI green. All of it happens before
`2.0.0-beta.1`.

1. **Fixes:** S9, S10. S11's verification goes in the same week.
2. **Repository hygiene:** S4 (model into the repository), S3 (freeze; announce it in the README).
3. **Removals inside the alpha:**
   1. S6 (`prefetch` options): JS, spec, both modules, tests.
   2. S7 (source sets): JS type, spec prop, the core functions and their tests, both views, smoke scenarios, and the lifecycle model's deferred-start action.
   3. S2 (in-app SwiftPM): manifest branch, CI job, `spm-assessment.md` gets a "deferred" note.
4. **S1 (seam internal):** a new ADR superseding 0003 and amending rule 1, then the code.
5. **Measurement:**
   - S5, the iOS bench.
   - S12, the event-mask A/B: keep or remove `loadEventMask`.
6. **Docs:**
   - The migration guide drops the removed features.
   - The README states the scope rule.
   - The S15 deprecations get development warnings.
7. **Beta.**

Re-run the lifecycle model after steps 3 and 4: both change the event alphabet
(the deferred start and the loader swap).

---

## The final question

> If we were rebuilding TurboImage today, knowing everything we know now,
> what is the simplest architecture we would confidently ship and maintain
> for the next five years?

**Almost exactly this one, about 15-20% smaller.** The layering is the
answer the project reached after 1.x:

- a thin Fabric component,
- a small C++ core that alone decides what a request means and what a view shows,
- each platform's mature engine doing all the loading behind an internal boundary.

I would keep every one of those layers. The C++ core is the one piece that
looks over-engineered at first glance, and it is the piece I would defend
hardest. It replaces two drifting ports with one exhaustively tested
implementation, and React Native's New Architecture already pays for the
toolchain.

What I would not ship is what this plan removes:

- a public loader-replacement contract,
- source sets,
- memory-targeted prefetch,
- a second, preview iOS integration path,
- features admitted without demand or measurement.

The rule that keeps it boring for five years is the scope rule. The core
holds meaning, lifecycle and pixels; the engines hold everything else; and a
new prop needs a user, a gap no existing prop fills, and, for performance
work, a number.
