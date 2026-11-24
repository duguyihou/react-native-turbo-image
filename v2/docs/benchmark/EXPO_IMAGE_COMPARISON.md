# TurboImage vs expo-image

Status, 2026-11-25: **the harness is built and validated. The measurements
that would settle the questions below have not been run yet.** They need
5+ iterations on a physical Android phone and an iPhone (see
[BENCHMARK_METHODOLOGY.md](BENCHMARK_METHODOLOGY.md)). What exists so far:

- one iteration of every preset on an **iOS simulator** (iPhone 16 Pro Max,
  iOS 18.6), raw output in `tmp/bench/ios-20261125-095929.jsonl`;
- one iteration on the **Android emulator**, in progress when this was
  written (`tmp/bench/android-*.jsonl`).

One run per library can't pass the significance test (that needs ≥ 5), so
every number here is labelled **preliminary**. Where a difference is large
*and* the source code explains it, this report says so. Nothing here is a
verdict yet.

Versions compared: TurboImage 2.0.0-alpha.0 (Nuke 14.0.0 / Coil 3.6.3),
expo-image 58.0.18 (SDWebImage 5.21.6 / Glide 5.0.5), React Native 0.88.1.
Details are in the methodology.

## The finding that changes how to read everything else

**expo-image's default `cachePolicy` is `'disk'`, which turns its memory
cache off** on both platforms. `ios/ImageView.swift` defaults to `.disk`,
which maps to `SDImageCacheType.disk`. `ExpoImageViewWrapper.kt` calls
`skipMemoryCache(true)` for every policy except `memory` and `memory-disk`.
TurboImage's default reads memory, then disk.

So a comparison of defaults partly measures that one default. The bench
runs expo-image twice to separate the two:

- `expo`: defaults;
- `expoMem`: `cachePolicy="memory-disk"`.

Where TurboImage beats `expo` but not `expoMem`, the difference is a
default that an app changes with one prop, not the engine.

## Preliminary observations (iOS simulator, 1 iteration)

A simulator runs on the Mac's CPU, GPU and memory, so treat these as
leads only.

| Preset · cache | Metric | turbo | expo | expoMem | Reading |
|---|---|---|---|---|---|
| load-100 · cold | last image (mount →) | 122 ms | 213 ms | 180 ms | TurboImage ahead in this run; needs repeats |
| load-100 · cold | peak footprint | 40 MB | 130 MB | 129 MB | large, and explained by the source (below) |
| pressure · cold (900 × 3000×2000) | peak footprint | 49 MB | 446 MB | **1438 MB** | large, and explained by the source |
| pressure · cold | first screen | 162 ms | 328 ms | 324 ms | lead |
| grid-fast · cold | destination screen after the fling | 33 ms | 45 ms | 37 ms | probably equivalent |
| remount · warm | final mount settles | 7 ms | 34 ms | 20 ms | lead; `expo` re-reads disk each time (no memory cache) |
| repeated · warm | requests | 0 | 0 | 0 | equivalent: all served from cache |
| cancel · cold | aborted downloads / requests | 6 / 36 | 6 / 36 | 6 / 36 | **equivalent**: all three cancel the abandoned in-flight downloads |
| cancel · cold | destination screen | 11.8 s | 11.9 s | 11.8 s | equivalent: bound by about six connections per host and 2 s bodies, not by the library |
| offline | – | – | – | – | not measured: the bench had a bug (the scenario never logged READY), fixed after this run |

**Why the memory gap is expected, not a fluke.** On iOS, expo-image decodes
the **full image**. It caches that full-size bitmap, and then redraws a
view-sized copy for display (`ImageView.swift` `processImage`). It decodes
at the view's size only with `tintColor`, `enforceEarlyResizing` or
photo-library assets (`ImageView.swift:236`). TurboImage decodes at the
view's size and caches that.

A 3000×2000 image is about 24 MB decoded, against a few hundred KB at cell
size. With `memory-disk`, those full-size decodes also stay in the memory
cache, which is where the 1.4 GB comes from. On a device the OS would evict
or kill the app long before that. **Expectation for the device run:**
TurboImage uses substantially less memory on iOS with large sources, and
the difference shrinks with sources near the view's size. On Android both
downsample at decode, so no such gap is expected there.

## Feature comparison (from the installed source)

| Capability | TurboImage 2.0 | expo-image 58 | Assessment |
|---|---|---|---|
| Request headers | `source.headers`: a record, pairs or a `Headers`-like object; validated in the core (CR/LF rejected) | `source.headers` | equal in practice |
| Cache policies | 5: `default`, `memoryOnly`, `noCache`, `cacheOnly`, `urlCache` (HTTP `Cache-Control`/ETag), the same on both platforms | 4: `none`, `disk`, `memory`, `memory-disk`; the default skips memory | TurboImage: `cacheOnly` (offline reads) and `urlCache` have no expo equivalent, and its default is the one most apps want |
| Cache configuration | `configureCache` on both platforms | `configureCache` on iOS only | TurboImage |
| Placeholders | blurhash, thumbhash, `{ uri }`, `require()` | blurhash, thumbhash, image, ImageRef; `generateBlurhashAsync`/`generateThumbhashAsync` | expo-image: it can generate hashes |
| Transitions | cross-fade only (`fadeDuration`, skipped on memory hits) | iOS: dissolve, flips, curls, SF Symbol effects; Android: fade | expo-image (more on iOS) |
| Transformations | `resize`, `blur`, `monochrome`, `tint`: one C++ implementation on both platforms, each variant cached in memory | `tintColor`, `blurRadius` (capped at 25 on Android, in software) | TurboImage: consistent across platforms, cached |
| Animated formats | GIF, APNG, WebP, SVG | GIF, APNG, WebP, SVG, **AVIF, HEIC**; `autoplay`, `startAnimating`/`stopAnimating` | expo-image |
| Prefetch | `prefetch(sources, { cachePolicy })`, to disk without decoding | `prefetch(urls, { cachePolicy, headers })`; on Android with a different downsample strategy from views, so memory keys likely don't match | TurboImage slightly (it states what it caches) |
| Size | `getSize` reads the header only | `loadAsync` → an ImageRef with width and height (decodes) | TurboImage, for size checks |
| Recycling | `recyclingKey`; keeps the old image until the new one loads unless the key changed | `recyclingKey` | equal |
| Load lifecycle | `onStart` → `onProgress` → `onSuccess`/`onFailure` → `onCompletion`, exactly one completion per start, `cancelled` for superseded loads; events with no handler aren't sent | `onLoadStart`, `onProgress`, `onLoad`, `onError` (suppressed on cancel), `onDisplay`; iOS reloads on every prop update and size change | TurboImage: a contract an app can rely on |
| Error handling | stable `code` on both platforms: `invalidRequest`, `notCached`, `network`, `decode`, `unknown` | an error message string | TurboImage |
| Accessibility | React Native's view accessibility props | the same, plus `alt` and `accessibilityElementsHidden` (iOS) | roughly equal; expo-image has `alt` |
| Live Text | iOS | iOS | equal |
| Platforms | iOS, Android, tvOS (simulator-tested); New Architecture only | iOS, Android, **web** | expo-image |
| TypeScript | full types, exported event types | full types | equal |
| Footprint | Nuke and Coil only, no Expo modules | requires `expo` / `expo-modules-core` in the app | TurboImage, for bare React Native apps |

Feature count isn't the measure. The differences that would matter in
production are:

- TurboImage's view-sized decode on iOS (memory);
- its lifecycle and error contract (correct UI state);
- `cacheOnly` and `urlCache` (offline and HTTP-correct caching).

expo-image's real advantages are AVIF/HEIC, richer transitions, web
support, hash generation and the Expo ecosystem.

## The seven questions: current answers

1. **Where is TurboImage objectively faster?** Not established. The
   single-run iOS simulator data leans TurboImage on `load` and `pressure`
   cold, but one run per library can't pass the test.
2. **Where is expo-image objectively faster?** Not established. No metric
   favoured expo-image in the iOS simulator run, but that's one run on a
   simulator.
3. **Where are they equivalent?** Preliminary: cancellation of abandoned
   downloads (identical server-side counts on iOS), request reuse for
   repeated URLs (0 requests warm for all), and fast-scroll destination
   time.
4. **Which uses less memory?** On iOS, very likely TurboImage, by a wide
   margin for images larger than their views. That's backed by both the
   measurements and the source. On Android, unknown until the device run.
5. **Which handles rapid scrolling better?** Not established. Android
   `gfxinfo` frame statistics from a phone are needed.
6. **Which has better lifecycle behaviour?** On the API contract,
   TurboImage: one completion per start, a `cancelled` state, stable error
   codes, no events with no handler. Observed cancellation was equivalent.
   expo-image on iOS reloads on every prop update and size change, which is
   extra work, though its effect hasn't been measured separately.
7. **Is TurboImage different enough to justify its maintenance?**
   Provisionally yes, *if* the device runs confirm the iOS memory gap. That
   gap, plus `cacheOnly`/`urlCache` and the lifecycle contract, are things
   expo-image can't match with a prop change. If the device runs show no
   memory or speed advantage, the case reduces to API design and a
   non-Expo dependency footprint, which is a much weaker reason to maintain
   two native pipelines.

## To finish

1. Attach an Android phone: `RUNS=5 bash scripts/bench-android.sh`, 10 presets ×
   3 libraries × 2 cache states × 5 runs = 300 launches, roughly 1–2 hours.
2. Rebuild the iOS bench (for the `offline` fix) and run
   `RUNS=5 bash scripts/bench-ios.sh "" <udid>` on an idle simulator; then
   repeat the key presets on an iPhone with Instruments.
3. Replace the preliminary table with `bench-summary.py`'s verdicts, and
   answer the questions from those.
