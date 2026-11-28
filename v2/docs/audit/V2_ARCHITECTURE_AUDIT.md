# TurboImage v2: architecture audit

Audited: branch `feat/v2-native-toolchain` at `3aee9ca`, 2026-11-25.
Companion documents: [`V2_SIMPLIFICATION_PLAN.md`](V2_SIMPLIFICATION_PLAN.md),
[`V2_API_RECOMMENDATION.md`](V2_API_RECOMMENDATION.md).

## How to read this

- `pkg/` stands for `v2/packages/react-native-turbo-image/`.
- Every claim carries a tag:
  - **[F] Fact:** read in the code or the repository's own records. File and symbol given.
  - **[M] Measured:** a number the repository records (`v2/docs/compatibility-matrix.md`, `SESSION.md`, commit messages). Not re-run for this audit.
  - **[H] Hypothesis:** plausible, not verified. Says how to verify.
  - **[R] Recommendation:** the plan document carries the detail.
- Method: I read the code and traced the load, prefetch, cancel and memory-hit paths through both platforms. Nothing was built or run for this audit, and no file outside `v2/docs/audit/` was changed.

## Verdict in one paragraph

The layering is sound, and most of it earns its keep. Nuke and Coil own
fetching, de-duplication, both cache tiers, decoding, downsampling and
animation. TurboImage owns what a request *means* and what a view *shows*.
It keeps that in one tested C++ core instead of two drifting ports. That is
the right split, and it is the main thing 1.x got wrong ([F] ADR 0001, 0010).
The over-engineering is not in the layering. It is in three places around it:

1. A **public, replaceable loader seam** that nothing uses.
2. **2.0 scope that went past parity.** It added 30 `feat` commits in 10 days, and each one widens the state the two views carry.
3. A **build and CI surface** that is larger than the product code it ships.

**Overall over-engineering risk: Medium.** It is trending toward High, because
features are still being added faster than they are being retired.

---

## 1. Architecture map

### 1.1 Layers and their size [F]

Production lines, excluding tests, from `wc -l`:

| Layer | Files | Lines | Role |
|---|---|---:|---|
| JS component + Codegen specs | `pkg/src/index.tsx`, `TurboImageViewNativeComponent.ts`, `NativeTurboImageModule.ts` | 809 | Prop normalisation, 1.x shims, indicator, statics |
| C++ core | `pkg/cpp/include/turboimage/*.h`, `pkg/cpp/src/*.cpp` | 2,247 | Request semantics, lifecycle, processors, hash decoders |
| ↳ request resolution and geometry | `ImageRequest.{h,cpp}` | 735 | Cache matrix, keys, decode size, `placeImage`, `chooseSource`, `needsLargerDecode` |
| ↳ lifecycle | `ViewLifecycle.{h,cpp}` | 393 | Effect-returning state machine |
| ↳ processors | `Processing.{h,cpp}` | 578 | resize, blur, monochrome, tint on RGBA8 |
| ↳ placeholders | `Placeholder.{h,cpp}` | 444 | blurhash, thumbhash |
| Android bridge to the core | `TurboImageJni.cpp` + `core/*.kt` | 704 + 669 | JNI entry points, Kotlin mirrors of the core's enums and state |
| Android view, manager, module, borders | `com/turboimage/*.kt`, `*.java` | 1,313 | Fabric host view, props, cache TurboModule |
| Android loader | `loader/*.kt` | 1,270 | Seam interface, Coil adapter, Coil setup, progress, APNG, header-size decoder |
| iOS Fabric (ObjC++) | `pkg/ios/Fabric/*` | 1,636 | Host view, cache module, `TIRequestFactory` |
| iOS seam (ObjC) | `pkg/ios/LoaderAPI/*` | 414 | `TIImageLoading`, `TIImageRequest`, registry |
| iOS Nuke adapter (Swift) | `pkg/ios/Nuke/*` | 960 | Two pipelines, variant index, decoders, CoreSVG |
| iOS Live Text | `pkg/ios/LiveText/*` | 83 | VisionKit interaction |
| Build manifests | `build.gradle`, two `CMakeLists.txt`, podspec, `Package.swift` | 626 | |
| Scripts | `v2/scripts/*` | 1,866 | Vendoring, version checks, smoke, bench, fixtures, evaluation |
| CI | `.github/workflows/v2-*.yml` | 641 | 8 job groups, including pre-release evaluation |
| Docs | `v2/docs/**/*.md` | 1,700 | RFC, 13 ADRs, plans |

Two ratios matter for the rest of this audit:

- **Glue to reach the core: about 1,600 lines** (JNI 704, Kotlin mirror 669, plus about 230 in `TIRequestFactory.mm`). That is about 70% of the core's own size.
- **Build, scripts and CI: 3,133 lines.** That is more than the JS layer and the Android view combined (2,122 lines), and close to the JS layer plus both native views (3,758 lines). The whole production codebase is about 10,100 lines.

### 1.2 Who owns what [F]

| Responsibility | Owner | Notes |
|---|---|---|
| HTTP fetch, connection pooling, TLS | Nuke (`DataLoader`/URLSession) and Coil (OkHttp) | One client per process (see §5.2) |
| Concurrent-request de-duplication | Nuke (task coalescing) and Coil (`DeDupeConcurrentRequestStrategy`) | Coil's is `@ExperimentalCoilApi` (`CoilLoaderSetup.kt:88`) |
| Memory cache | Nuke `ImageCache` and Coil `MemoryCache` | One per process, isolated from the host app's |
| Disk cache (original bytes) | Nuke `DataCache` and Coil `DiskCache` | 150 MB on both |
| HTTP-freshness cache (`urlCache`) | Second Nuke pipeline + private `URLCache`; Coil `CacheControlCacheStrategy` | **TurboImage-added**: `PolicyCacheStrategy` picks one per request |
| Downsampling while decoding | Nuke thumbnails (ImageIO) and Coil sizing (`inSampleSize`) | TurboImage decides only the target |
| Decoding of stills and animated formats | ImageIO/Nuke, NukeUI player; Coil `AnimatedImageDecoder`/`GifDecoder`, LINE APNG | **TurboImage-added**: `ContentDecoder`, `AnimationSources` (iOS), `ApngDecoder` (Android) |
| SVG | iOS: private CoreSVG via `dlsym` (**TurboImage-owned**). Android: `coil-svg` | ADR 0008 |
| Processors | **TurboImage C++ core** | Coil 3 has no transformations library (ADR 0007) |
| Placeholder decoding | **TurboImage C++ core** | Byte-exact against the JS references |
| Cache-key canonicalisation, policy matrix, decode target | **TurboImage C++ core** | |
| What is on screen, event ordering | **TurboImage C++ core** (`ViewLifecycle`) | |
| Fade | iOS: the view (`UIView.transition`). Android: Coil `crossfade` | |
| Reattach and restart on detach | Coil `ImageViewTarget`; iOS has no equivalent need | |
| Progress | Nuke progress stream; **TurboImage `ProgressInterceptor`** on OkHttp | Coil has no progress API |
| Prop delivery, events, view recycling | React Native Fabric, Codegen | |
| Borders on Android | React Native `BackgroundStyleApplicator`, routed by `TurboImageBorders` | Fills an RN gap for Codegen managers |

### 1.3 Duplicated responsibilities

- **[F] None of Nuke's or Coil's core infrastructure is re-implemented.** There is no custom memory cache, disk cache, HTTP client, decoder queue or request queue. This is the most important finding, and it is good.
- **[F] Indexing on top of the engines:**
  - The iOS variant index (`NukeImageLoader.swift:82-101`, `rememberLocked` at `:392`) exists because Nuke's memory cache cannot be enumerated. Coil's can, so Android scans keys instead (`CoilImageLoaderAdapter.memoryKeysFor`).
  - Both are justified by `dispose` and the `memoryCacheKey` placeholder. Both are consequences of view-sized decoding, which multiplies memory keys per image.
- **[F] Coil internals relied on.** `COIL_SIZE_EXTRA = "coil#size"` (`CoilRequests.kt:100`) and `TRANSFORMATIONS_EXTRA = "coil#transformations"` (`CoilImageLoaderAdapter.kt:353`) are Coil's private extra names. A test pins them (`CacheTest`). This is a maintenance liability on every Coil upgrade, but a contained one.
- **[F] Deliberate duplicate store.** `urlCache` keeps a second disk store, so one image can sit on disk twice (ADR 0002). It is documented and accepted.

---

## 2. Execution paths traced

### 2.1 A view load, iOS [F]

1. `updateProps` notes what changed. `finalizeUpdates` builds the core `ImageRequest` (`coreRequest`) and compares it with `_loadedRequest`.
2. `reload` calls `TIMakeImageRequest`, which calls `resolveRequest` and converts the result to a `TIImageRequest` (16-argument initialiser). It then hands `ViewLifecycle::reload` and its effects to `perform:step:`.
3. `StartLoad` emits `onStart`, then calls `[sharedLoader loadImageWithRequest:…]`.
4. `NukeImageLoader.loadImage` translates the request to a Nuke `ImageRequest`. On a memory hit it completes **synchronously inside the call** (`:218-227`); otherwise it opens an image task and a progress task.
5. The completion passes `loadSucceeded(token)` to the lifecycle, gets `DeliverSuccess` and `EmitCompleted` back, then shows the image through `displayImage:animation:inImageView:` and records it as upgradable.

### 2.2 A view load, Android [F]

1. The manager setters copy props into `view.request` (a Kotlin data class). `onAfterUpdateTransaction` calls `onTransactionEnd`, which compares a `LoadInputs` value.
2. `reload` resolves through JNI (`nativeResolve`), then gets the lifecycle effects through JNI (`nativeLifecycleReload`, state in a `LongArray(5)`).
3. `startLoad` calls `CoilImageLoaderAdapter.load(view, …)`, which builds the Coil request with `KeepCurrentImageTarget`, `LaidOutSizeResolver`, crossfade and progress token.
4. Coil paints the `ImageView`. The listener calls `onSuccess`, the view calls `loadSucceeded` (JNI) and emits events. A completed request is disposed so Coil does not replay it on reattach (`CoilImageLoaderAdapter.kt:~85-100`).

### 2.3 Cancel and supersede [F]

- On both platforms a superseded load gets `CancelLoad` + `EmitCancelled` from the core, and its late callbacks find a dead token and get no effects. Android's adapter additionally guards with `finished` and `dispose()`.
- This is double protection. It is cheap, and it is correct, because ADR 0004 says the Android adapter paints without the view's say.

### 2.4 Prefetch [F]

- JS `prefetchTarget` (`src/index.tsx:481`) picks `'disk'` or `'memory'` and a width. The module resolves through `resolveForCache` (`TurboImageCore.kt:86`, and `TIMakeImageRequest` on iOS), turns the memory write off for `'disk'`, and calls the adapter's `prefetch`.
- That fetches bytes only: Android uses `HeaderSizeDecoder`, iOS uses `pipeline.data(for:)`.

---

## 3. Complexity analysis by layer

The verdicts used below:

- **Justified:** solves a real, present problem at a fair price.
- **Over-built:** a real problem, solved bigger than needed.
- **Speculative:** solves a problem nobody has yet.

### 3.1 TypeScript layer

| Abstraction | Problem it solves | Verdict |
|---|---|---|
| `TurboImageComponent` wrapper | Normalises 1.x prop forms, `require()`, headers in three forms | **Justified.** Thin: no loading logic in JS [F] |
| `indicator` container (ADR 0009) | 1.x spinner | **Justified for compatibility**, but it moves `ref`/`testID` and remounts on toggle [F]. A 3.0 removal candidate |
| `rounded` | 1.x circle crop | Now only `borderRadius: 9999` + `overflow: hidden` [F]. **Redundant**; keep as an alias |
| `contentPosition` parser | expo-image parity | **Justified** in JS. The cost is in the native placement (§3.3, §3.4) |
| `prefetch` `{resize}` / `'original'` | Warm the memory cache for a view | **Over-built.** Matches only views with exactly that `resize` and no other processing [F] (`PrefetchOptions` doc comment). On iOS a layout-sized view cannot be prefetched into memory at all [F] (`SESSION.md`) |
| `loadEventMask`, `progressEnabled` (internal Codegen props) | Skip building events JS will drop | `progressEnabled` is **justified**: it stops byte counting and main-thread hops. `loadEventMask` is **unmeasured** [F] (commit `3aee9ca`: "Unmeasured; React Native's `<Image>` gates its load events the same way") |
| 1.x type aliases, `dataCache` shim, `format` / `isProgressiveImageRenderingEnabled` | Migration | **Justified until 3.0**, already marked `TODO: remove in 3.0` [F] |

Events keep 1.x's names (`onStart`, `onSuccess`, `onFailure`, `onCompletion`),
not React Native's (`onLoadStart`, `onLoad`, `onError`, `onLoadEnd`). I would
not add aliases: that doubles the surface for a naming preference.

### 3.2 C++ core

| Part | Problem | Real and present? | Verdict |
|---|---|---|---|
| `resolveRequest`, cache matrix, `canonicalCacheKey`, header validation | 1.x disagreed per platform on keys, policies and error text [F] ADR 0001 | Yes | **Justified.** About 120 lines of logic, exhaustively tested |
| `DecodeSize` / `vectorDecode` | The decode target and SVG sizing must match | Yes | **Justified.** The SVG branch adds real subtlety (ADR 0008) |
| `ViewLifecycle` (effect machine) | Ordering bugs in hand-mirrored flags [F] ADR 0010 | Yes | **Justified.** Also covered by an exhaustive-order GoogleTest and a TLA+ model. The model is outside the repository: see §8 |
| `ProgressThrottle` | Same `onProgress` cadence on both platforms | Marginal | **Over-built** for its value (47 lines + two JNI calls), but harmless |
| `placeImage`, `chooseSource`, `largerSourceFor`, `needsLargerDecode` | Same geometry on both platforms | Partly | Pure and cheap. Each also costs a JNI entry and a Kotlin wrapper. `chooseSource` and `largerSourceFor` exist only for source sets (§3.5) |
| `Processing` | Identical pixels; no Coil 3 transformation library | Yes | **Justified.** Costs CPU: 12 MP blur 100-130 ms on an M-series host [M], never measured on a phone |
| `Placeholder` | Four hand ports in 1.x | Yes | **Justified** |

**On "should this be C++ at all":** the alternative is a Swift and a Kotlin port
checked against shared test vectors. That is cheaper to build: no JNI, no
mirrored enums, no `static_assert`s, no NDK step. But it is exactly what 1.x
had, and 1.x drifted (ADR 0001 records the `cacheOnly` example). The New
Architecture already makes C++ part of every app build, and React Native
requires the NDK. So the marginal cost is the JNI glue, not a new toolchain.
**[R] Keep the core. Freeze its scope:** it holds decisions that need
cross-platform identity *and* exhaustive testing, not every pure function.

### 3.3 iOS layer

| Abstraction | Problem | Verdict |
|---|---|---|
| ObjC seam `TIImageLoading` (ADR 0003) | Swift adapter vs ObjC++ view without Swift/C++ interop | **The language boundary is justified.** Making it a *public, replaceable* extension point is **speculative** (§3.6) |
| `TIImageLoaderRegistry` + `NSClassFromString(@"TurboImageNukeLoader")` (`TIImageLoaderRegistry.m:51`) | Avoids a LoaderAPI → Nuke dependency cycle | **Over-built.** The cycle exists only because the registry lives in LoaderAPI. The Fabric target already links `TurboImageNuke` (`Package.swift`), and under CocoaPods it is one module. [H] Fabric can reference the class through the generated Swift header; verify on both integration paths |
| `TIImageRequest` (16-arg designated init) | Carries the resolved request across the language boundary | **Justified** given the boundary. It is verbose but mechanical |
| Two Nuke pipelines + private `URLCache` (`:135-166`) | `urlCache` must obey HTTP freshness; `DataCache` cannot | **Justified** while `urlCache` exists |
| Variant index + amortised sweep (`:82-101`, `:392-406`) | Nuke memory cache not enumerable; needed by `dispose` and the `memoryCacheKey` placeholder | **Justified.** A sweep on main is 2.3 ms for 2,000 variants on the simulator [M] |
| `AnimationSources` (`NukeDecoders.swift:100`) | Share frames between differently sized decodes of one animation | **Justified** by ADR 0012's memory goal |
| Synchronous memory-hit completion (`:218-227`) | No blank frame on recycled cells | **Justified.** Do not simplify |
| `TIImageContainer` + `placeImage` | `contentPosition`, and `center` drawn at the wrong size because decodes are at scale 1 | **Justified**, but the `center` fix is a workaround for decoding at scale 1 |
| CoreSVG via `dlsym` | SVG without a dependency | A knowingly accepted App Review risk (ADR 0008) |

The custom view classes are thin, and there is no custom request pipeline.
Nuke is used through its public API apart from the processor-identity trick
(`ImageProcessors.Anonymous(id:)` to address entries). The Nuke integration
is thin.

### 3.4 Android layer

| Abstraction | Problem | Verdict |
|---|---|---|
| `ImageLoaderAdapter` interface | Seam (rule 1); test fake (`TurboImageViewTest.kt:472`) | The **interface is justified as a test seam**. The **public replaceability** (`TurboImageLoaders.set`, `TurboImageLoaders.kt:48`) and the "an adapter written before X keeps compiling" defaults (`ImageLoaderAdapter.kt:71`, `:87`) are **speculative** |
| One `ImageLoader` and one `OkHttpClient` per process (`TurboImageLoaders.get`, `buildImageLoader`) | Correct ownership | **Justified.** There is no per-image allocation of either (§5.2) |
| `KeepCurrentImageTarget` (`CoilRequests.kt:191`) | Coil's target would wipe the TurboImage placeholder | **Justified**, small |
| Dispose-after-complete | Coil replays a view's last request on reattach | **Justified.** A real bug class with FlatList `removeClippedSubviews` |
| `LaidOutSizeResolver` (`:244`) | Fabric leaves `WRAP_CONTENT` params; Coil's `ViewSizeResolver` decoded originals | **Justified**, with its reasoning recorded |
| `VectorSizeDecoderFactory`, `VECTOR_SIZE_EXTRA` | `allowDownscaling={false}` must not shrink SVGs | **Over-built** for a narrow case (a processed SVG with downscaling off), but it is isolated |
| `PolicyCacheStrategy` | Per-request choice of HTTP freshness | **Justified** while `urlCache` exists. Uses an experimental Coil API |
| `ProgressInterceptor` with token header | Coil has no progress API | **Justified.** Gated by `progressEnabled` |
| User-Agent interceptor | Some hosts refuse OkHttp's default (Wikimedia 403) | **Justified** |
| `TurboImageBorders` + Java `TurboImagePropsDelegate` | Codegen managers get no border props on Android | **Justified.** Fills a React Native gap |
| Matrix placement with the "nudge" double set (`applyPlacement`) | `setScaleType` after the first layout never applies | **Justified workaround** for an ImageView quirk |
| `startWhenLaidOut`, `pendingStart`, `hasLayout` (`TurboImageView.kt:463`) | Choosing a source-set candidate needs a size | **Exists only for source sets.** Removed with them |
| Upgrade machinery (`:579`) | View outgrows its decode | **Justified** as the price of downscale-by-default (§3.5) |

The context ownership is correct: the adapter holds `applicationContext`,
and views hold their `ThemedReactContext` [F]. There is no unnecessary Kotlin
abstraction beyond the seam.

### 3.5 Feature-driven complexity in the views

The two views are where scope accumulates. Each feature adds a field, a branch
and a test dimension to **both** views:

| Feature | Per-view state it adds | Assessment |
|---|---|---|
| `recyclingKey` | `recyclingKeyChanged` | Core value for FlashList |
| Placeholders (hash, `memoryCacheKey`, `uri`) | `placeholderHandle`/`_placeholderTask`, generation | Core value. `memoryCacheKey` partly overlaps `{uri}` |
| Silent upgrades (ADR 0013) | `Upgradable`, `upgrading` token in the lifecycle, upgrade callbacks | **Justified pairing** with default downscaling. Without it, a rotation or expanding card stays blurry |
| Source sets | `candidates`, `_loadedCandidates`, `_upgradableCandidate`, `pendingStart`, `hasLayout` | **Optional.** No recorded demand. The Android pre-layout path exists only for it |
| `contentPosition` / `scale-down` | `contentPositionX/Y`, matrix (Android), container frame (iOS) | Optional, contained |
| Live Text | `_liveText`, `_needsLiveTextUpdate` | Optional, iOS-only, contained |

### 3.6 The replaceable-loader seam (architecture rule 1)

- **[F]** `architecture.md` rule 1: "An app can replace the adapter: `TIImageLoaderRegistry.sharedLoader` on iOS, `TurboImageLoaders.set` on Android."
- **[F]** ADR 0004: "There is one Android adapter, and no second one planned", and the Android seam is shaped around Coil's `ImageView` target.
- **[F]** The seams carry backward-compatibility defaults for third-party adapters that do not exist (`loadPlaceholder` and `imageSize` defaults; `@optional imageSizeForRequest:`).
- **[F]** `SESSION.md` lists two behaviour gaps that exist only because the loader can be swapped: views made under a replaced loader keep the old loader's image view.

The internal boundary is worth keeping: a language boundary on iOS, and a
test fake on Android. The *public* promise is speculative extensibility. It
commits the project to a stable adapter contract for five years in exchange
for a use case nobody has asked for.

### 3.7 New Architecture integration

- **[F]** Fabric-only, with no legacy-architecture code paths. **Correct**: it removes a whole axis.
- **[F]** No custom ShadowNode, no C++ state, no custom ComponentDescriptor. Codegen props plus `finalizeUpdates`/`onAfterUpdateTransaction` batching. **Minimal, good.**
- **[F]** TurboModule sources are `UnsafeObject`, re-validated by the core. **Pragmatic**: it avoids Codegen struct wrappers.
- **[F]** Internal props (`progressEnabled`, `loadEventMask`) ride in the public Codegen spec, marked "Not a public prop". Acceptable.
- Nothing here is built for hypothetical requirements.

---

## 4. Native dependency audit

Classification key: **E** essential, **U** useful but optional, **D** duplicated native functionality, **X** unnecessary complexity.

| Capability | Who implements it | Custom code | Class |
|---|---|---|---|
| Image loading | Nuke / Coil | Translation only | E |
| Request cancellation | Nuke task / Coil `dispose` | Token guard in the core | E |
| Request de-duplication | Nuke coalescing / Coil `DeDupe…` | None | E (engine) |
| Memory cache | Engines | Variant index (iOS), key scan (Android) | U: needed by `dispose` and the `memoryCacheKey` placeholder |
| Disk cache | Engines | None | E (engine) |
| HTTP cache (`urlCache`) | URLCache / Coil cache-control | Second pipeline, `PolicyCacheStrategy`, disk-key prefix | U: a 1.x compatibility feature |
| Decoding | Engines | `ContentDecoder` routing (iOS) | E |
| Downsampling | Engines | Target decided by the core; `LaidOutSizeResolver` | E |
| Transformations | **Core C++** | 578 lines + JNI bitmap path | U: justified by cross-platform identity |
| Progressive rendering | Not implemented | `isProgressiveImageRenderingEnabled` ignored | Correctly deferred |
| Animated formats | NukeUI player; Coil decoders + LINE APNG | `AnimationSources`, `ApngDecoder` | U |
| SVG | CoreSVG (private) / coil-svg | `CoreSVG` dlsym wrapper, `VectorTarget`, `VectorSizeDecoderFactory` | U, with accepted review risk |
| Prefetch | Engines | Disk-only path via header decoding; memory targeting | Disk prefetch E; memory targeting **X** |
| Lifecycle (attach/detach) | Coil target / Fabric recycle | Dispose-after-complete | E |
| Memory pressure | Engines (Nuke `ImageCache` trims on warnings; Coil `MemoryCache` trims on `onTrimMemory`) | None | E (engine). [H] Not exercised by any test (`SESSION.md`: "a frame pool under memory pressure" untested) |
| Network behaviour | URLSession / OkHttp | Timeouts, User-Agent, no cookie jar | E |
| Progress | Nuke stream / custom OkHttp interceptor | `ProgressInterceptor`, core throttle | U |
| Placeholder decoding | **Core C++** | 444 lines | U |

There are no **D** entries: TurboImage does not re-implement anything the
engines already provide.

---

## 5. Performance and reliability

### 5.1 What is measured [M]

| Measurement | Source | Result |
|---|---|---|
| Android `load`, 30 images, Galaxy S25, median of 5 | `compatibility-matrix.md:55` | Large cold 313 vs 314 ms (expo-image); large warm 104 vs 194 ms; photo cold 69 vs 54 ms; photo warm 51 vs 79 ms |
| Android memory | same | PSS 105-111 MB vs 141-192 MB (30-40% lower) |
| Android main-thread work for 30 views | `SESSION.md` | ~5 ms (library 0.8, adapter 1.6, reloads 2.6) |
| Core blur, 12 MP | `SESSION.md` | 100-130 ms, host CPU, not a phone |
| Placeholder decode | `SESSION.md` | ~0.2 ms (9×9 blurhash), host |
| iOS variant sweep | `SESSION.md` | 2.3 ms / 2,000 variants, simulator |

### 5.2 Checks requested by the brief

| Concern | Finding |
|---|---|
| Per-image `ImageLoader` | **[F] No.** One adapter per process (`TurboImageLoaders.get`), and views receive it |
| Per-image `OkHttpClient` | **[F] No.** Built once inside `buildImageLoader` and handed to Coil as `callFactory`. [H] Coil memoises that factory; a one-line identity test would pin it |
| Per-image Nuke pipeline | **[F] No.** Two per process, created once |
| Unbounded caches | **[F] No** for the engines' caches. **[F]** `AnimationSources` is weak-valued and never pruned of dead keys beyond `NSMapTable`'s own behaviour (`SESSION.md`). Low risk |
| Bridge traffic | **[F]** Progress is gated, events are gated, and progress is throttled to about 100 per load |
| Duplicate requests | **[F]** Coalesced by both engines. On Android, followers get no progress |
| Retained views and callbacks | **[F]** iOS blocks use `weakSelf`. Android listeners close over the view, but Coil's `ViewTarget` disposal and `finished` flags bound them. [H] There is no leak test (LeakCanary or Instruments) |
| Main-thread blocking | **[F]** Disk ops off main on Android (`diskExecutor`); placeholder decode off main on both; processing on the engines' queues. The iOS variant sweep runs on main (measured above) |
| JNI per lifecycle step | **[F]** One JNI call with a `LongArray(5)` copy per step, plus one per progress callback before the throttle. [H] Sub-microsecond. Not worth optimising without a measurement |
| Low-memory devices | **[F]** Android memory cache defaults to 25% of the app's memory; Nuke's defaults scale with the device. [H] Untested on a low-RAM device |
| Network interruption | **[F]** A 504 under `cacheOnly` is classified `notCached`, otherwise `network`. No retry policy, correctly left to the app |

### 5.3 Gaps

- **[F] iOS has no benchmark.** `apps/bench` is Android-only (`SESSION.md`). Every iOS performance statement is theoretical.
- **[F] No rapid-scroll benchmark exists** for dropped frames or cancellation rate on either platform. The `grid` FlashList scenario exists for Android only.
- **[F] `loadEventMask`** was merged without a measurement.

### 5.4 Benchmarks proposed

1. **iOS bench parity:** port `apps/bench`'s `load` and `grid` scenarios to iOS against expo-image. Measure last-image time and `phys_footprint`.
2. **Fast fling:** a FlashList of 500 rows, flung programmatically. Record dropped frames (Android `FrameMetrics`, iOS `CADisplayLink` hitches), loads started, loads cancelled, and bytes fetched for cancelled loads.
3. **Memory soak:** scroll 2,000 distinct images and record the peak and settled footprint, then fire a simulated memory warning or `onTrimMemory(RUNNING_CRITICAL)`. Checks that engine trimming reaches TurboImage's isolated caches.
4. **Event-mask A/B:** 30-image cold screen, mask forced to 15 vs computed, JS-thread busy time. It decides whether `loadEventMask` stays.
5. **JNI cost:** a micro-benchmark of 10,000 lifecycle steps through JNI. It closes the question in §5.2.
6. **Upgrade frequency:** count upgrades per screen in the example app during rotation and card expansion. It tells whether ADR 0013 fires in practice.
7. **Low-end Android:** the `load` scenario on a 2-3 GB RAM device (Android Go).

---

## 6. Cross-platform consistency

**Differences that are correct and should stay** [F]:

- **Who paints** (ADR 0004). Forcing symmetry would lose Coil's target lifecycle.
- **iOS pauses animations** under Reduce Motion or Auto-Play off. This is platform correctness, not drift.
- **SVG engines differ** (CoreSVG vs AndroidSVG).
- **Platform-only props:** `allowHardware` (Android) and `enableLiveTextInteraction` (iOS).
- **`dispose` / `clearDiskCache` can reject on Android only.** Coil deletes synchronously; Nuke stages removals.

**Symmetry that costs more than it buys:**

- **`ProgressThrottle` in the core:** it equalises a cadence no app depends on. Cheap, so not worth removing, but not worth extending.
- **Upgraded animations:** Android restarts the animation, while iOS skips animated images. That inconsistency is unforced. [R] Skip animated drawables on Android too.

**Inconsistencies that are bugs:** see §8.

---

## 7. Build and dependency complexity

| Item | Necessary? | Note |
|---|---|---|
| CocoaPods + vendored Nuke/NukeUI xcframeworks | **Yes.** Nuke left CocoaPods trunk at 9.5 [F] | 10.3 MB tarball, reproducible build script, dSYMs for device slices |
| SwiftPM `Package.swift`, standalone mode | **Yes.** Hosts the adapter tests (`test-ios-adapter.sh`) | |
| SwiftPM `Package.swift`, in-app mode (`isInsideReactNativeApp`) | **No, not yet.** React Native's SPM is preview, and the manifest depends on the app's build layout (`docs/spm-assessment.md`) | It carries its own CI job (`ios-spm-app`) and the "rule 6" parity burden |
| CMake + NDK + JNI | **Yes**, given the core | Apps already need the NDK for React Native |
| Gradle Kotlin ≥ 2.3 and React Native ≥ 0.88 checks | **Yes.** They turn a confusing metadata failure into a clear message | |
| `native-versions.env` + `check-native-versions.sh` | **Yes.** Cheap, and prevents drift between three manifests | |
| tvOS slices and support | **Optional.** Never run on a device, and no smoke suite [F] | Adds slices and a CI build |
| React Native 0.89 pre-release evaluation in CI | **Optional.** Non-blocking | About 140 lines of workflow + `eval-rn-version.sh` |
| `coil-network-cache-control` | Only for `urlCache` | Experimental API |
| LINE `apng` | Only for APNG on Android | Native `.so`, 16 KB-aligned [F] |
| Bun + oxlint/oxfmt monorepo | Fine | Hoisted linker is required by React Native tooling (ADR 0005) |

**[H] Duplicate `Nuke` module.** An app that already links Nuke itself (through
SwiftPM or its own vendored copy) and also installs TurboImage through
CocoaPods may get two `Nuke` modules or duplicate classes. **Verify:** build the
example with `Nuke` added as an app-level SwiftPM dependency, under static and
dynamic linkage.

---

## 8. Correctness findings

These are small and verified. No P0 issue was found.

| ID | Finding | Evidence | Severity |
|---|---|---|---|
| C1 | **iOS does not re-apply the placeholder when only `placeholder.uri` changes.** Android does: its `placeholderUri` setter sets `needsPlaceholder`. | `pkg/ios/Fabric/TurboImageComponentView.mm:336-340` compares `blurhash`, `thumbhash` and `memoryCacheKey` only | P2, **fixed** (test `testANewPlaceholderUriAloneReplacesThePlaceholder`) |
| C2 | **The JNI ABI guard misses `ResizeMode::ScaleDown` (4).** Kotlin mirrors it as `SCALE_DOWN(4)`, but the file's header comment says every mirrored value is asserted. | `pkg/android/src/main/cpp/TurboImageJni.cpp:47-50`; `core/ImageRequest.kt:34` | P2, **fixed** |
| C3 | **The lifecycle's TLA+ model lives only in the gitignored `.claude/`.** It is a verification asset for the riskiest code, and exists in one clone. | `/.claude/` in `.gitignore:89`; `SESSION.md` "Test coverage gaps" | P1 (maintainability) |
| C4 | **Android upgrades restart animated images, while iOS skips them.** | `TurboImageView.kt:574-578` TODO; `TurboImageComponentView.mm:701-709` | P3 |

---

## 9. Over-engineering scorecard

### Criteria

The score measures **engineering balance**: what the complexity buys,
relative to what it costs to keep. It does not measure features.

- **9-10:** nothing to remove; every part has a present, demonstrated reason.
- **7-8:** small, isolated excess.
- **5-6:** a sound core, with noticeable speculative or scope-driven excess.
- **3-4:** the excess dominates maintenance.
- **1-2:** the structure itself is the problem.

### Scores

| Category | Score | Why |
|---|---:|---|
| Architecture simplicity | 6 | Clean layers, with engines doing the heavy lifting. Docked for the public seam and the registry indirection |
| API simplicity | 5 | Parity shims plus seven 2.0 additions. `prefetch` options leak cache-key reasoning to users |
| Native integration simplicity | 6 | Thin over Nuke and Coil, but relies on Coil-internal key names. Variant index and animation sharing on iOS |
| State management simplicity | 6 | One lifecycle owner (good). Views still carry about 10 auxiliary fields each, many from optional features |
| Dependency complexity | 7 | Few dependencies, all pinned and checked. Experimental Coil APIs in two places |
| Build complexity | 4 | Dual iOS integration, a vendored binary build, a JNI layer, about 3,100 lines of build, scripts and CI for about 10,100 lines of product |
| Performance engineering | 7 | Downscale by default and synchronous memory hits are measured wins on Android. iOS is unmeasured, and some micro-optimisations are unmeasured |
| Maintainability | 5 | Excellent tests and decision records. A large surface for one maintainer, docs cross-referenced by rule number, and the model check outside the repository |
| Developer experience | 6 | Clear failure messages, 1.x compatibility. Kotlin 2.3, iOS 16 and Xcode 27 floors are steep |
| **Overall engineering quality** | **6** | A good design with roughly 15-20% of its surface not yet earning its keep |

**Overall over-engineering risk: Medium,** trending High at the current rate:
136 commits in 10 days, 30 of them `feat`.

### Three biggest sources of unnecessary complexity

1. **The public, replaceable loader seam** (rule 1, `TIImageLoaderRegistry`, `TurboImageLoaders.set`, backward-compatibility defaults). It is speculative extensibility with a five-year contract attached.
2. **Scope beyond parity in the views:** source sets, memory-targeted prefetch, tvOS. Each multiplies view state and the test matrix with no recorded user demand.
3. **Build and CI breadth:** in-app SwiftPM (preview), the pre-release evaluation matrix, and about 1,900 lines of scripts. The release infrastructure is larger than the product's JS layer and either native view.

### Three areas where complexity is justified

1. **The C++ core for request semantics and the view lifecycle.** 1.x's drift is documented, and one exhaustively tested copy is cheaper than two that disagree.
2. **Processors and hash decoders in C++.** Coil 3 has no transformation library, and the output is byte-identical across platforms.
3. **Decode-to-view-size, its cache keying, and the silent upgrade that makes it safe.** The memory win is measured (PSS 30-40% below expo-image).

### Three things that should NOT be simplified

1. **Token-guarded callbacks and the exactly-once `onStart` → `onCompletion` pairing,** including the Android adapter's `finished` and `dispose` double guard (ADR 0004 makes cancel load-bearing there).
2. **One isolated pipeline per process.** Do not share the host app's Nuke or Coil singletons, and do not create loaders per view.
3. **Synchronous memory-hit completion (iOS) and dispose-after-complete (Android).** They prevent recycled-cell flicker and stale repaints on reattach, bugs that only show in production lists.
