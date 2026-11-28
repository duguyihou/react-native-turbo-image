# TurboImage 2.0 example app

A small React Native app that uses the workspace's `react-native-turbo-image`
(`packages/react-native-turbo-image`, linked by `workspace:*`, so it always
runs the library as it is in this checkout). It has three jobs:

- **Show the API**: the Gallery, Image detail and Playground screens.
- **Check a real integration**: the smoke test, which CI runs on an iOS
  simulator and an Android emulator.
- **Reproduce performance problems**: the Performance screen, with fixed
  datasets of 100 to 1000 images.

All commands below run from `v2/` unless they say otherwise.

## Install

Requirements: Bun 1.3.13, Node ≥ 22.11, Xcode 27 with an iOS simulator,
CocoaPods, JDK 17 and the Android SDK (see `docs/compatibility-matrix.md`
for the pinned versions).

```sh
bun install                         # all workspaces; hoisted node_modules
```

### iOS setup

```sh
bun run vendor:nuke                 # Nuke.xcframework + NukeUI.xcframework, from the pinned tag
(cd apps/example && bun run pods)   # pod install; also runs iOS Codegen
```

Re-run `bun run pods` after changing the library's Codegen spec
(`src/TurboImageViewNativeComponent.ts`). iOS Codegen runs there, not in the
Xcode build.

### Android setup

Nothing beyond the SDK: Gradle fetches Coil. Start an emulator or connect a
device with USB debugging.

## Run

Two terminals:

```sh
bun run fixtures                    # 1. the image server, kept running (Ctrl-C stops it)
(cd apps/example && bun run start)  # 2. Metro
```

Then launch the app, from Xcode (`apps/example/ios/TurboImageExample.xcworkspace`)
or Android Studio (`apps/example/android`), or:

```sh
(cd apps/example && bun run ios)
(cd apps/example && bun run android)
```

**Why a local server.** Every remote image comes from
`scripts/fixture-server.py`, not from the internet. Runs are the same every
time, work offline, and the server can do what the demos need: refuse a
header, revalidate with an ETag, send a body slowly, return HTML instead of
an image, and count the requests it gets. `bun run fixtures` also runs
`adb reverse tcp:8765 tcp:8765` for every attached Android device; run it
again after an emulator restarts. If the server is not reachable, every
screen shows a banner saying so.

A physical iPhone cannot reach the Mac's `localhost`. Start the server with
`bun run fixtures --host 0.0.0.0` and set `BASE` in `src/fixtures.ts` to the
Mac's LAN address.

Measure performance in a **release** build: a debug build runs the JS
unoptimised and adds the developer tools' overhead.

```sh
(cd apps/example && bun run build:ios:release)       # simulator .app under ios/build
(cd apps/example && bun run build:android:release)   # app-release.apk, R8, arm64-v8a
```

## Screens

| Screen | Shows |
|---|---|
| Home | A quick-start snippet and the way in to everything else. |
| Gallery | A remote URL and a `require()` asset, a 600×400 and a 3000×2000 photo in the same frame (with the decoded sizes `onSuccess` reports), the five resize modes, blurhash, thumbhash and `{ uri }` placeholders, `borderRadius` corners, a loading spinner driven by `onStart`/`onCompletion`, and failures with and without `showPlaceholderOnFailure`. Tap an image to open it in Image detail. |
| Image detail | One image and its event log, with timings. You can switch the source: photo, large, slow, bundled, GIF, APNG, WebP, SVG, text (Live Text), request headers accepted (200) and refused (406), 404, not an image, not cached, `ftp://`, ETag. Each source comes with a note on what to look for. Also covers the five cache policies, the cache statics (`prefetch`, `getSize`, `dispose`, `clearMemoryCache`, `clearDiskCache`) with their results and timings, and the processors (`resize`, `blur`, `monochrome`, `tint`). |
| Performance | See [Performance testing](#performance-testing). |
| Playground | Every public 2.0 prop, with the JSX for the current settings. It leaves out the deprecated 1.x props and `recyclingKey`, which only matters in a recycling list. |
| Smoke test | The CI suite (below). |

The app follows the system's light or dark appearance.

## Architecture

```
apps/example/
  App.tsx                  the navigation stack and deep links
  src/startup.ts           TurboImage.configureCache, before any image
  src/fixtures.ts          the server's address, URL helpers, the demo sources
  src/screens/*.tsx        Home, Gallery, Detail, Performance, Playground
  src/smoke/SmokeTest.tsx  the smoke suite
  src/events.tsx           the event log used by Detail and Playground
  src/ui.tsx, theme.ts     the shared components and the light/dark colours
  src/ServerBanner.tsx     the "fixture server not reachable" banner
  fixtures/                the images the server sends
```

Choices that keep it small:

- **No navigation library.** There are five screens, a stack is a list in
  state, and Android's back button pops it. A native stack would add
  react-native-screens, one more native dependency to build on every React
  Native version the library supports. The cost: there is no iOS
  swipe-back, and a screen unmounts when you leave it. That unmounting is
  useful, because leaving a screen tears down its images the same way every
  time.
- **No state library.** Each screen keeps its own state. The Performance
  counters live in a ref, because 1000 cells setting state on every event
  would measure React rather than TurboImage.
- **FlatList, not FlashList.** No new dependency. `apps/bench` already covers
  FlashList, comparing TurboImage with expo-image and RN's `<Image>`.
- **No app-only native code.** The app's only native change is the
  `turboimageexample://` URL scheme in `Info.plist` and
  `AndroidManifest.xml`, which the deep links below need.

The only runtime dependencies are `react`, `react-native`,
`react-native-safe-area-context` and the library itself.

### Deep links

The first screen can be chosen from the command line, which scripted runs use:

```sh
# iOS simulator: the link as a launch argument (relaunches the app)
xcrun simctl terminate booted org.reactjs.native.example.TurboImageExample
xcrun simctl launch booted org.reactjs.native.example.TurboImageExample \
  -launchURL 'turboimageexample://performance?count=1000&dataset=repeated'
# Android
adb shell am start -a android.intent.action.VIEW \
  -d 'turboimageexample://performance?count=1000&dataset=repeated' com.turboimageexample
```

On iOS, `xcrun simctl openurl booted '<link>'` works too, but iOS first asks
"Open in TurboImageExample?", which a script cannot answer. The
`-launchURL` argument lands in `NSUserDefaults`, where the app reads it
through React Native's `Settings`. The argument lasts for that launch only.

| Link | Opens |
|---|---|
| `turboimageexample://smoke` | the smoke test |
| `turboimageexample://gallery`, `…://playground` | that screen |
| `turboimageexample://detail?source=gif` | Image detail on a source (ids in `src/fixtures.ts`) |
| `turboimageexample://performance?count=…&dataset=…&autorun=…` | Performance: `count` 100, 500 or 1000; `dataset` `unique`, `repeated`, `large` or `slow`; `autorun` `scroll` or `remount` |

## Smoke test

53 scenarios, each checking one cross-platform contract through the real view
and loader: cache policies and keys, placeholders, headers, every failure
code, animated formats, SVG sizes, processing, downscaling, event order,
cancellation, recycling, the cache module. When they have all settled, the
screen logs one line: `TURBOIMAGE_SMOKE {"pass":true,...}`.

```sh
(cd apps/example && bun run build:ios:release) && bash scripts/smoke-ios.sh
(cd apps/example && bun run build:android:release) && bash scripts/smoke-android.sh
```

The scripts reinstall the app (so the caches are cold), start the fixture
server, launch it on `turboimageexample://smoke` and wait for the line. You can also
open the smoke test from Home, but after the other screens have run the
caches are warm, so a failure there proves nothing until you reproduce it
with the scripts.

## Performance testing

The Performance screen is a 3-column FlatList over one of four fixed
datasets:

| Dataset | URLs | What it shows |
|---|---|---|
| Unique | N distinct 600×400 JPEGs (28 KB) | a feed |
| Repeated ×12 | 12 URLs repeated over N rows | request reuse: the server should see about 12 requests, however many rows |
| 3000×2000 | N distinct 368 KB JPEGs | decoding big images into small cells |
| Slow | N distinct 3000×2000 JPEGs, each sent over about 2 s | cancellation: scrolling past a cell must abandon its download |

The URLs never change between runs. A second run of a dataset therefore
starts with a warm disk cache, and you can only get a cold run by pressing
**Clear disk** and **Clear memory**, or by reinstalling.

The scenarios:

- **Fast scroll**: a scripted pass to the end and back, at ¼, 1 or 3 screens
  per frame, with `scrollToOffset` once per `requestAnimationFrame`. The steps
  are fixed, so every run scrolls the same way.
- **Remount ×20**: unmounts the list for one frame, then mounts it for 250 ms,
  twenty times. This is what a user opening and leaving a screen quickly
  looks like to TurboImage.
- **Remount**: mounts the list once, from scratch.
- **Screen navigation**: leave the screen and come back. Each screen
  unmounts when you leave it.
- **Offline and recovery**: stop `bun run fixtures` (Ctrl-C) and scroll to
  rows that haven't loaded. They fail with `network`. Start the server
  again and press **Remount**. TurboImage never retries a failed load by
  itself, so the rows load only once they mount again.

### What the numbers are

Each number on the screen comes from something real. The labels say where
from, and anything the app cannot measure is greyed out instead of guessed.

| Shown | Source | Note |
|---|---|---|
| onStart / onSuccess / onFailure (by code) / completed as cancelled | Each cell's event handlers, counted in JS | A load whose view unmounts sends no further events, so "starts with no completion yet" is not the same as "in flight". |
| First / last onSuccess since mount | The JS clock (`performance.now()`) from the list's mount | Includes the time events take to reach JS. |
| Scroll pass | The number of `requestAnimationFrame` steps and the time they took | The JS thread's frame rate during the pass. It does not measure the UI thread. |
| Requests for this dataset | The fixture server's count since the last reset (`/__hits?prefix=`) | The real network traffic: request reuse, coalescing and cache hits show up as fewer requests than rows. |
| Bodies aborted by the client | Responses the client closed while the server was still writing them | Evidence that an in-flight download was abandoned. It means something only for **Slow**, because a fast body has been sent in full before any cancel can arrive. Remount does not trigger it: the remounted cells ask for the same URLs a frame later, so the pipeline may keep the download. |

**Not measured in the app**, so measure these with the platform tools:

- **UI frame rate.** Use the Perf Monitor in the dev menu (debug builds), or
  Xcode Instruments (Animation Hitches) and Android Studio's profiler (or
  `adb shell dumpsys gfxinfo com.turboimageexample`) on release builds.
- **Memory.** Use Xcode's memory gauge or Instruments (Allocations), and on
  Android `adb shell dumpsys meminfo com.turboimageexample` or Android
  Studio's memory profiler. Watch the numbers over several Remount ×20 runs:
  steady growth is a leak, while a plateau is the memory cache filling up.
- **Cache hit rate.** TurboImage does not report which tier served a load,
  so the app does not guess at it. Comparing onSuccess with the server's
  requests gives the share of loads served without a request: memory, disk
  and coalesced loads together.

### Recipes

| Problem | Steps | Expected |
|---|---|---|
| Request reuse | Clear disk, Clear memory, Reset counts; Repeated ×12, 1000 images; Fast scroll | Server requests ≈ 12 |
| Cancellation | Clear disk, Clear memory, Reset counts; Slow, 500 images; Fast scroll at 3 screens/frame; Refresh server counts | Server requests far below onStart, because loads still queued (about six per host run at once) never reach the wire. **Unverified**: in the runs of 2026-11-25, "bodies aborted" stayed 0 on both platforms. Read it as "no in-flight body was seen abandoned", not as proof that cancellation works. |
| Disk cache | Unique, 100; wait for the first screen; Remount | onSuccess climbs; server requests stay flat |
| Memory growth | 3000×2000, 1000; Remount ×20 three times while you watch the memory tool | Memory levels off instead of growing with each run |
| Offline recovery | Unique, 500; scroll part-way; stop the server; scroll on; start it again; Remount | Failures counted as `network`, then the rows load |

For scripted runs, `autorun` in the deep link starts a scenario a second
after the list mounts. When it ends, the app logs one line:

```sh
xcrun simctl launch booted org.reactjs.native.example.TurboImageExample \
  -launchURL 'turboimageexample://performance?count=1000&dataset=slow&autorun=scroll'
xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "TURBOIMAGE_PERF"'
# Android: adb logcat -s ReactNativeJS:V | grep TURBOIMAGE_PERF
```

`TURBOIMAGE_PERF {"scenario":"scroll","count":1000,"dataset":"slow","starts":…,"server":{"count":…,"aborted":…},"scrollFrames":…,"scrollMs":…}`

Release builds log it at error level, which iOS keeps. For timing
comparisons between libraries, use `apps/bench`.

## Platform differences

These are differences in TurboImage itself, and the demos show them as they
are:

- **SVG**: `onSuccess` reports the view's size on Android, where the SVG is
  drawn for the view, and the canvas size on iOS, where it stays a vector.
  When processed, both rasterise at the view's size.
- **Cookies**: iOS sends the cookies `fetch` stored in `HTTPCookieStorage`,
  and Android sends none. Use `source.headers` or signed URLs for images
  behind a login.
- **`allowHardware`** is Android-only. **`enableLiveTextInteraction`** is
  iOS-only (not tvOS). The Playground says so next to each.
- **`urlCache`**: on iOS it keeps its own 150 MB store and never stores
  responses over 7.5 MB.
- **Animated images on iOS** show their first frame only while Reduce Motion
  is on, or Auto-Play Animated Images is off.
- **Android's per-host limit**: OkHttp runs at most five requests per host at
  once. More than five loads that never finish starve the rest, which the
  Slow dataset can show if cancellation regresses.
- **Physical devices**: Android uses `adb reverse`. An iPhone needs the LAN
  address (see [Run](#run)).

## Known limitations

- Every dataset serves one photo under many names, so a recycled row that
  briefly shows the previous row's image looks the same as the right one.
  Only the index label tells the rows apart.
- There is no in-app measurement of UI frame rate or memory. See above.
- On iOS there is no swipe-back gesture. Use the Back button.
- `BASE` is fixed in source code, so a physical iPhone needs an edit.
