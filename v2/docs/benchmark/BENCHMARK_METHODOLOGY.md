# Benchmark methodology: TurboImage vs expo-image

How `apps/bench` and `scripts/bench-{android,ios}.sh` compare
react-native-turbo-image with expo-image, and what their numbers can and
cannot support. The findings are in
[EXPO_IMAGE_COMPARISON.md](EXPO_IMAGE_COMPARISON.md).

## What is compared

| | TurboImage | expo-image |
|---|---|---|
| Package | `react-native-turbo-image` 2.0.0-alpha.0 (this workspace) | `expo-image` 58.0.18, with `expo` 58.0.26, `expo-modules-core` 58.1.0 |
| iOS engine | Nuke 14.0.0, vendored `Nuke.xcframework`, built from source | SDWebImage 5.21.6, with SDWebImageAVIFCoder 0.12.0, SDWebImageSVGCoder 1.8.0, SDWebImageWebPCoder and libavif, **precompiled**: Expo SDK 58's default (`EXPO_USE_PRECOMPILED_MODULES=1`) ships ExpoImage as a release xcframework |
| Android engine | Coil 3.6.3 (`coil-core`, `coil-network-okhttp`, `coil-network-cache-control`, `coil-gif`, `coil-svg`) | Glide 5.0.5 with its OkHttp 3 integration, androidsvg 1.4, APNG/WebP via penfeizhou glide-plugin 3.0.5, AVIF integration |
| Shared | React Native 0.88.1, New Architecture, Hermes, React 19.3.0, FlashList 2.3.2 | same |

Versions come from the installed packages (`node_modules/*/package.json`,
`expo-image/android/build.gradle`, `expo-image/spm.config.json`,
`apps/bench/ios/Podfile.lock`, `scripts/native-versions.env`), not from
documentation.

Both libraries are linked into the same app (one APK, one iOS app), but
**only one library renders per launch**: the deep link picks it, and the
other is never touched. Each launch is a fresh process.

## The app (`apps/bench`)

`adapters.tsx` has one small component per library with the same props:

- a square of `CELL` points (a third of the screen width), `cover`;
- `recyclingKey` set to the image's index (both support it; FlashList
  recycles views);
- the library's own "load began" event (`onStart` / `onLoadStart`) and
  "loaded" event (`onSuccess` / `onLoad`, fired when decoded, before it is
  drawn), and its error event;
- **every other prop at its default.** That includes caching, downscaling,
  priority and transitions. A benchmark of defaults measures what an app
  gets without tuning. The cost is that a default that differs between the
  libraries is part of the result: see [Known asymmetries](#known-asymmetries).

expo-image runs twice, as two "libraries":

| Name | Props | Why |
|---|---|---|
| `turbo` | defaults | |
| `expo` | defaults | what an app gets without tuning |
| `expoMem` | `cachePolicy="memory-disk"` | expo-image's default `cachePolicy` is `'disk'`, which **skips its memory cache** on both platforms (`ios/ImageView.swift`: `cachePolicy = .disk`, mapped to `SDImageCacheType.disk`; `ExpoImageViewWrapper.kt`: `skipMemoryCache(true)` unless the policy is memory or memory-disk). TurboImage's default reads memory, then disk. `expoMem` caches like TurboImage. |

A result where TurboImage beats `expo` but not `expoMem` comes from
expo-image's default cache policy, which an app can change with one prop,
not from its engine. The summary therefore compares TurboImage with each
variant separately.

There is no shared abstraction beyond those props: each adapter calls the
library's component directly.

## Datasets

All images come from `scripts/fixture-server.py` on the host, over HTTP/1.1
with keep-alive. Android reaches it through `adb reverse`, the simulator
through the Mac's loopback. That controls the network and "CDN" completely:
the same bytes, no rate limits, no third-party variance. The cost is that it
is not a real network: no TLS, no HTTP/2, near-zero latency. Results
therefore show the cost of each library's own pipeline (queueing, decoding,
caching, main-thread work), not of the internet.

| Source | Bytes | Size |
|---|---|---|
| `photo` | 28 KB JPEG | 600×400 |
| `large` | 368 KB JPEG | 3000×2000 |
| `slow` | `large`, sent in 4 KB chunks 20 ms apart (about 2 s) | 3000×2000 |

URLs are `/<source>/<scenario>-<index>.jpg`, or `-r<index mod 12>` for
`repeated`. They are stable across runs, so a warm run finds what the cold
run cached. Distinct URLs are distinct cache entries for both libraries.

## Scenarios

Each preset (`scripts/bench-common.sh`) is one deep link, runnable on its
own: `PRESETS="cancel" RUNS=5 scripts/bench-android.sh`.

| Preset | What happens | Main question |
|---|---|---|
| `load-100`, `load-500`, `load-1000` | N `photo` images mounted at once in a wrapping `View`, without virtualization | throughput, and latency under a full queue |
| `grid-paced` | A 900-image FlashList scrolled one screen per 300 ms, animated | steady scrolling |
| `grid-fast` | The same, one screen per frame, not animated | a fling that outruns the loader; how fast the destination fills |
| `repeated` | `grid-fast` over 12 URLs | request reuse and coalescing |
| `remount` | One screen mounted for 250 ms and unmounted for a frame, 20 times, then mounted for good | leftover work from unmounted views |
| `cancel` | A screen of `slow` images starts; 300 ms later the list jumps to its end and stays | whether abandoned downloads are cancelled, and whether they delay the new screen |
| `pressure` | `grid-fast` over 900 distinct `large` images | memory under decode pressure |
| `offline` | Server stopped at launch; every image of one screen fails; the script starts the server; the app remounts the screen | recovery, and whether a failure sticks |

**Cold and warm.** Every preset runs in both states:

- cold: Android `pm clear` and iOS uninstall and reinstall, so there is no
  disk cache, no memory cache and a fresh process;
- warm: the app is terminated and relaunched, so the disk cache is kept and
  memory is empty.

Neither state uses the library's own cache-clearing API, which would
measure that API instead.

**Order and repetition.** `RUNS` iterations (default 5, the minimum the
statistics below can use). Within an iteration the libraries alternate
order (A B, then B A), so a device warming up or throttling over the
session hits both alike. Cold and warm runs of one library are adjacent.

## Metrics

Every metric is labelled with its origin. **Direct** means measured as
reported. **Derived** means computed from direct metrics. Anything else is
**unavailable** and is not shown.

### From the app (JS clock, `performance.now()`)

The app records the first "load began" and first "loaded" event of each
image, by index, and nothing more.

| Metric | Origin | Meaning |
|---|---|---|
| `firstMs`, `p50Ms`, `p95Ms`, `lastMs` | direct | mount → each image's "loaded" event: time to first image, median, P95, total |
| `latencyP50Ms`, `latencyP95Ms` | direct | each image's "load began" → "loaded": the library's own pipeline, queueing included |
| `firstScreenMs` | direct | `grid`: mount → the first screen has settled |
| `lastScreenMs` | direct | `grid`, `cancel`: scroll end (or jump) → the destination screen has loaded |
| `failed` | direct | images whose error event fired |

These include the time an event takes to reach JS, which is part of what an
app experiences. Each library's "load began" event fires at a slightly
different point in its pipeline. That is why the mount-based metrics are the
primary comparison, and the start-based latency is secondary.

### From outside the app

| Metric | Origin | How |
|---|---|---|
| `requests` | direct | the fixture server's request count across the whole server, after minus before the run (`/__hits?prefix=/`). Only the app under test talks to it. |
| `aborted` | direct | responses the client closed while the server was still writing the body. Meaningful only for `slow` bodies: a fast body has been sent in full before any cancel arrives. A cancel that happens before the request is sent (still queued) is invisible here. |
| `servedWithoutRequestPct` | derived | 1 − requests / loaded images: the share of loads served by memory cache, disk cache or a coalesced request together. This is **not** a cache hit rate by tier. Neither library reports which tier served a load, so per-tier hit rates are unavailable. |
| `peakMemMb`, `endMemMb` | direct | Android: `dumpsys meminfo` TOTAL PSS, sampled about once a second. iOS simulator: `footprint` (phys_footprint) of the app's process every 0.5 s. The peak is the highest **sample**, which can miss a shorter spike. |
| `jankyPct` | derived | Android: janky frames / total frames from `dumpsys gfxinfo`, reset when the app logs READY. |
| `frameP95Ms` | direct | Android: the 95th-percentile frame time from `gfxinfo`. |

### Unavailable

- **Frame statistics on iOS.** The simulator renders with the Mac's GPU, so
  its frame times describe the Mac. On a device, record the
  Animation Hitches template in Instruments while the menu runs `grid-fast`
  (see [iOS on a device](#ios-on-a-device)).
- **Native object lifecycles** (live request, task and bitmap counts).
  Neither library exposes them, and adding probes would mean modifying a
  library. The `aborted`, `requests` and `remount` results are the
  observable evidence of lifecycle behaviour. The Android
  Profiler / Instruments Allocations can show live `Bitmap`/`UIImage`
  counts by hand.
- **FPS from JS.** It is deliberately not measured: a `requestAnimationFrame`
  counter reports the JS thread, not rendering.
- **Cache hit rate per tier.** See `servedWithoutRequestPct`.

## Statistics

`scripts/bench-summary.py` groups runs by platform, device, preset, cache
state and library. For every metric it reports the median and P95 across
iterations (nearest rank; with 5 runs the P95 is the maximum). For
TurboImage against expo-image it gives a verdict:

- **better / worse** only if a two-sided **exact Mann–Whitney U test** gives
  p < 0.05 **and** the medians differ by more than 5%;
- **no significant difference** otherwise.

Mann–Whitney is used because run times are skewed and n is small. With 5
runs per library, p < 0.05 needs the two sets to be almost completely
separated (the exact minimum p is 0.008). With 3 runs it is impossible
(minimum p = 0.1), which is why 5 is the floor. No correction for multiple
comparisons is applied, and with about 15 metrics × 10 presets × 2 states,
a few "significant" results are expected by chance. Treat an isolated win as
a lead to re-run with `RUNS=10`, not as a finding.

Raw output: `tmp/bench/<platform>-<timestamp>.jsonl`, one JSON object per
run with the device, the app's result line, the server counts before and
after, memory and frame stats. The summary is written next to it as
`.summary.json`.

## Controlling the environment

| Variable | Control |
|---|---|
| Device model, OS | recorded in every row (`device`); compare only rows from one device |
| React Native, build | one Release build per platform, both libraries in it; Android R8 `assembleRelease`, `arm64-v8a` only; iOS Release for the simulator |
| Network, CDN | the local fixture server (see [Datasets](#datasets)) |
| Image sizes, formats | fixed JPEG fixtures; the same URLs for both libraries |
| Cache state | cold or warm, set by the script before each launch |
| List | the same FlashList configuration, cell size and scroll script |
| Duration | scenarios end on an event (all settled), with a 60 s cap that marks the run `timedOut` |
| Thermal state, background load | not controlled; mitigated by interleaving. Close other apps, keep the screen on and the device off the charger if it throttles while charging |

### Physical devices

The scripts are written for them. For **Android**, connect a phone with USB
debugging and run `scripts/bench-android.sh`. Emulator results are recorded
as such (`"emulator": true`) and should not be quoted as performance claims:
the repository's own notes record an emulator gap against expo-image that a
phone did not reproduce.

### iOS on a device

`bench-ios.sh` drives a **simulator** only (`simctl`). A simulator shares
the Mac's CPU, GPU and memory and has no jetsam limit. Its numbers are good
for catching regressions and large differences, but not for claims about
iPhones. On a device:

1. Build the bench for the device in Release and install it from Xcode.
2. Open the menu, pick a run, and record it with Instruments: Animation
   Hitches for frames, Allocations or VM Tracker for memory, Network for
   requests. The fixture server must be reachable from the phone (start it
   with `--host 0.0.0.0`, and set `BASE` in `apps/bench/App.tsx` to the
   Mac's LAN address).
3. Repeat five times per library, alternating.

TODO: drive a device with `xcrun devicectl` (install, launch with
`-launchURL`, read the log) once one is available to test against.

## Known asymmetries

Differences the benchmark keeps, because each is part of what a library
does by default. They are named here so a result is read correctly:

- **Transitions.** TurboImage cross-fades for 300 ms by default
  (`fadeDuration`, skipped for memory-cache hits). expo-image has no
  transition unless one is set (`src/utils.ts` `resolveTransition`).
  Neither affects the "loaded" event, but a fade is extra drawing during
  scrolling, and frame statistics include it.
- **Where downscaling happens** (iOS). expo-image decodes the full image,
  caches that, and redraws a view-sized copy after the load when
  `allowDownscaling` is on. It decodes at the view's size only with
  `tintColor`, `enforceEarlyResizing` or photo-library assets
  (`ios/ImageView.swift` `processImage`, `ImageUtils.swift`). TurboImage
  decodes at the view's size and caches that. Expect different memory on
  `large` images for that reason. On Android both downsample at decode.
- **Reloads on prop updates** (iOS). expo-image reloads after every prop
  update and every change of the view's size, with no check that the source
  changed (`ImageModule.swift`, `ImageView.swift`). That is its behaviour,
  so it stays in.
- **Precompiled vs source builds** (iOS). ExpoImage and SDWebImage arrive as
  Expo's prebuilt release xcframeworks. TurboImage and Nuke are compiled in
  the app's Release build. Both are optimised builds.
- **The "load began" event.** Each library fires it at its own point (see
  [Metrics](#from-the-app-js-clock-performancenow)). It may also be skipped
  for memory hits; `withStart` in the raw output counts the images that had
  one.
- **Downscaling.** Both have `allowDownscaling` on by default. On Android
  both downsample while decoding, by different rules (Coil to the view's
  size; Glide's `ContentFitDownsampleStrategy`). On iOS only TurboImage
  does (see "Where downscaling happens"). expo-image does not report its
  decoded size, so the bench can't check that the pixel counts match.
- **Glide module.** expo-image registers Glide's `AppGlideModule`. That is
  why `apps/bench` cannot also compare react-native-fast-image (see
  `adapters.tsx`).
