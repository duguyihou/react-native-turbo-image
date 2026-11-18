# Migrating from 1.x to 2.0

For app developers. The reasons behind each change are in the [RFC](rfc/0001-turbo-image-2-native-toolchain.md); how the port was staged is in the [migration plan](migration-plan.md).

2.0 keeps the 1.x JavaScript API: every 1.x prop, event, static method and exported type still exists, so most apps need to change very little code. What changes is the platform underneath, a few defaults, and some behaviour that 1.x got wrong or left platform-specific.

## 1. Check the requirements

| | 1.x | 2.0 |
|---|---|---|
| Architecture | Old or New | **New Architecture only** |
| React Native | not pinned | **0.88 or newer** |
| iOS | 13.0 | **15.1** |
| Android | the app's `minSdk` | `minSdk` **24**, **Kotlin 2.3 or newer** |
| tvOS | listed in the podspec | not supported |

If your app is still on the Old Architecture, stay on 1.x until it has moved.

The Kotlin floor comes from Coil 3.6.3. React Native 0.88's app template ships Kotlin 2.2, so most apps have to raise it in `android/build.gradle`. Change both lines: the template declares the Kotlin Gradle plugin without a version, so setting `kotlinVersion` alone leaves the compiler at 2.2.

```diff
  buildscript {
    ext {
-     kotlinVersion = "2.2.0"
+     kotlinVersion = "2.4.21"
    }
    dependencies {
-     classpath("org.jetbrains.kotlin:kotlin-gradle-plugin")
+     classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
  }
```

An app whose Kotlin compiler is too old fails at Gradle configuration with a message that names the version it found.

## 2. Install

```sh
npm install react-native-turbo-image@next
cd ios && pod install
```

- **The pod is renamed** from `react-native-turbo-image` to `TurboImage`. Autolinking handles it. If your `Podfile`, a `post_install` hook or a build script names the old pod, update the name.
- **Gifu and APNGKit are gone.** Animated images are decoded with ImageIO. If your app depended on those pods only through TurboImage, they disappear from `Podfile.lock`.
- **Nuke is vendored** as a prebuilt `Nuke.xcframework` inside the package (13.2.3), so there is nothing extra to add to the `Podfile`.

### Optional: Swift Package Manager on iOS

CocoaPods is the default and the supported path. React Native 0.88's SwiftPM integration is a preview; TurboImage works with it, and CI builds it, but it is not what we recommend for production yet.

```sh
npx react-native spm add
```

## 3. Change your code

Only three things need an edit in a typical app.

### `cachePolicy="dataCache"` → `"default"`

```diff
- <TurboImage source={{ uri }} cachePolicy="dataCache" />
+ <TurboImage source={{ uri }} cachePolicy="default" />
```

`dataCache` still works throughout 2.x and logs a warning in development. It will be removed in 3.0. `default` is also what you get with no `cachePolicy` at all.

2.0 has five policies, the same on both platforms:

| Policy | Memory | Disk | Network |
|---|---|---|---|
| `default` | read, write | read, write (keyed by `cacheKey` or the URL) | yes |
| `memoryOnly` | read, write | none | yes |
| `noCache` | none | none | yes |
| `cacheOnly` | read | read | **never** |
| `urlCache` | read, write | the HTTP cache, obeying `Cache-Control` | yes |

`urlCache` is the only policy that honours `Cache-Control`, `ETag` and `no-store`, and in 2.0 it does so on Android too (1.x: iOS only). It keeps its own disk store, so a `cacheOnly` load does not see what a `urlCache` load stored on disk, and the reverse.

### Lists that reuse views need `recyclingKey`

When `source` changes, 2.0 keeps the previous image on screen until the new one has loaded, so a changed URL swaps without a blank frame. In a list that reuses views (FlashList), that means a reused row would briefly show the previous row's image. Give each image a key that identifies its content:

```diff
  <TurboImage
    source={{ uri: item.avatarUrl }}
+   recyclingKey={item.id}
  />
```

When the key changes together with the source, the view is blanked (or shows its placeholder) first. This is the same contract as expo-image's prop of that name.

### `source` may be a number

`source` now also accepts a `require()`d asset. TypeScript code that reads `.uri` off `TurboImageProps['source']` must narrow it first:

```ts
const uri = typeof source === 'number' ? undefined : source.uri;
```

## 4. Behaviour that changed

Nothing here needs a code change to compile, but each can change what your app does.

### Sizes and memory

- **Images are decoded no larger than their view.** A 12 MP photo in a thumbnail costs the thumbnail's memory. `onSuccess` therefore reports the decoded size, not the source's.
- A view that is zoomed, or that grows after its image loaded, shows the smaller decode scaled up. Set `allowDownscaling={false}` for those.
- Downscaling is not applied with `resizeMode="center"` or with `blur` without `resize`.

### Events

- `onFailure` gains `code`: `'invalidRequest' | 'notCached' | 'network' | 'decode' | 'unknown'`, the same on both platforms. Branch on `code`; the `error` text is diagnostic and differs between platforms.
- `onCompletion` can report `state: 'cancelled'` when a load is superseded by a newer one. A cancelled load reports neither success nor failure. Every `onStart` is answered by exactly one `onCompletion`.
- `onProgress` is throttled to about 100 events per load.

### Placeholders, fade and the indicator

- `fadeDuration` defaults to 300 ms on Android too (1.x Android: 100 ms). Set `fadeDuration={100}` to keep the old timing.
- The fade now also runs from a placeholder to the image. 1.x forced it to 0 there; set `fadeDuration={0}` to keep that. Memory-cache hits never fade.
- Passing more than one placeholder kind throws in development only. In release builds native picks one; 1.x threw in every build.
- `showPlaceholderOnFailure` without a `placeholder` does nothing. 1.x threw.
- `placeholder.memoryCacheKey` accepts either the URI or the explicit `cacheKey` the other image was loaded with.
- `indicator` appears only for loads that take longer than 150 ms, so cache hits never flash it, and it is never shown together with a `placeholder`.

### `rounded`, `indicator` and `ref`

1.x always wrapped the image in a container view. 2.0 adds the container only when `rounded` or `indicator` needs it.

- `ref` is the outermost view either way (the one that has `style`), so measuring works as before.
- `testID`, accessibility props and `onLayout` go to the image view, as in 1.x. With a container that is the inner view.
- Switching `rounded` or `indicator` on or off for a mounted image adds or removes the container, which remounts the image view and restarts its load. If you toggle either at runtime, keep it constant and change the style instead.

### Caching and the network

- `Cache-Control` headers are ignored except under `cachePolicy="urlCache"`.
- `TurboImage.prefetch` resolves `false` when any source fails. 1.x always resolved `true`.
- `TurboImage.dispose` now removes the image from memory and disk. It did nothing in 1.x.
- On Android, `dispose` and `clearDiskCache` reject with code `disk` if the disk cache cannot be written to.
- Scheme and host are lower-cased and the `#fragment` is dropped when a URL becomes a cache key, so `HTTPS://CDN.example.com/a.png#x` and `https://cdn.example.com/a.png` share one entry. An explicit `cacheKey` is used as written.
- `source.headers` are sent with the request but are not part of the cache key. A header with CR, LF or NUL in its value, or a name that is not an HTTP token, fails the load with `invalidRequest`.
- Local sources (`file://`, `content://`, `android.resource://`, `require()`) are never copied into the disk cache, and `cacheOnly` does not block them.
- On Android, requests send a descriptive `User-Agent` (`<App>/<version> TurboImage/<version> (Android <release>)`) instead of OkHttp's default, which some CDNs refuse.
- On Android, TurboImage no longer shares React Native's `OkHttpClient`, so cookies set through React Native's networking are not sent with image requests. Pass what the server needs in `source.headers`.

### Processors

- `resize`, `blur`, `monochrome` and `tint` are now one cross-platform implementation, so results differ slightly from 1.x on both platforms.
- `blur` is a Gaussian σ in pixels of the (resized) image. On Android it now applies at the original size, not the view's, so the same value looks weaker on a large photo. Pair it with `resize`.
- A `monochrome` colour's alpha is now the effect's intensity.
- Processors on an animated image produce a static image on iOS too. 1.x iOS ignored the processors and animated the raw data.

### Formats

- `format` is ignored: GIF, APNG, animated WebP and SVG are detected from the bytes. You can delete the prop.
- `isProgressiveImageRenderingEnabled` is ignored. It had no effect in 1.x either.
- On iOS an animation is shown as its first frame if all its frames, at the size they are decoded at, would exceed 64 MB.

## 5. SVG on iOS and App Review

2.0 renders SVG on iOS the way 1.x did: through Apple's CoreSVG framework, which is private. The functions are looked up at run time (`dlsym`), so if a future iOS removes them, an SVG fails to load (`onFailure` with `code: 'decode'`) instead of crashing the app.

This is the same technique [SDWebImageSVGCoder](https://github.com/SDWebImage/SDWebImageSVGCoder) uses, and its maintainers report having shipped App Store apps with it. It is still private-API use, and Apple could flag it in review. If that risk is not acceptable for your app, do not load SVG through TurboImage on iOS: convert the assets to PDF or PNG, or render them with a library such as react-native-svg.

Android uses `coil-svg` and has no such concern.

## 6. Checklist

- [ ] App is on the New Architecture, React Native 0.88+, Kotlin 2.3+, iOS 15.1+
- [ ] `Podfile` and scripts no longer name the `react-native-turbo-image` pod
- [ ] `cachePolicy="dataCache"` replaced with `"default"`
- [ ] Images in recycled lists have a `recyclingKey`
- [ ] Code that reads `source.uri` handles a numeric source
- [ ] `onFailure` handlers branch on `code`
- [ ] Zoomable or growing images set `allowDownscaling={false}`
- [ ] Android image requests that relied on cookies now send `source.headers`
- [ ] `format` and `isProgressiveImageRenderingEnabled` removed
- [ ] You have decided whether SVG through CoreSVG is acceptable on iOS
