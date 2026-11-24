# Migrating from 1.x to 2.0

For app developers. The reasons behind each change are in the [RFC](rfc/0001-turbo-image-2-native-toolchain.md); how the port was staged is in the [migration plan](migration-plan.md).

2.0 keeps the 1.x JavaScript API: every 1.x prop, event, static method and exported type still exists, so most apps need to change very little code. What changes is the platform underneath, a few defaults, and some behaviour that 1.x got wrong or left platform-specific.

## 1. Check the requirements

| | 1.x | 2.0 |
|---|---|---|
| Architecture | Old or New | **New Architecture only** |
| React Native | not pinned | **0.88 or newer** |
| iOS | 13.0 | **16.0**, built with **Xcode 27 or newer** |
| Android | the app's `minSdk` | `minSdk` **24**, **Kotlin 2.3 or newer** |
| tvOS | listed in the podspec | **16.0**, with [react-native-tvos](https://github.com/react-native-tvos/react-native-tvos) 0.88 or newer |

If your app is still on the Old Architecture, stay on 1.x until it has moved.

An app on React Native older than 0.88 fails at `pod install` and at Gradle configuration with a message that names the version it found.

On Apple TV, `enableLiveTextInteraction` does nothing: tvOS has no Live Text. Everything else is the iOS implementation. tvOS support is new: it has been built and run in a fresh react-native-tvos 0.88 app on the simulator, not yet on a device (see the compatibility matrix). Two things an Apple TV app may need, neither specific to TurboImage:

- **Installed with npm:** react-native-tvos 0.88's `@react-native-tvos/virtualized-lists` makes npm install upstream React Native beside the fork, and two React Natives in one bundle break native components (`View config getter callback for component ... must be a function`). Check with `npm ls react-native`, and fix it with an override in `package.json`:

  ```json
  "overrides": { "react-native": "npm:react-native-tvos@0.88.1-0" }
  ```

- **Built with Xcode 27:** the app must adopt the UIScene lifecycle, or UIKit stops it at launch. React Native 0.88's iOS template has a `SceneDelegate`; react-native-tvos's template (0.83) does not yet.

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

The iOS floor comes from Nuke 14. React Native 0.88's app template targets iOS 15.1, so most apps have to raise it too, in the `Podfile` and in the app target's **Minimum Deployments** setting in Xcode (`IPHONEOS_DEPLOYMENT_TARGET`):

```diff
- platform :ios, min_ios_version_supported
+ platform :ios, '16.0'
```

With a lower target, `pod install` stops with a message that the `TurboImage` pod needs a higher minimum deployment target.

## 2. Install

```sh
npm install react-native-turbo-image@next
cd ios && pod install
```

- **The pod is renamed** from `react-native-turbo-image` to `TurboImage`. Autolinking handles it. If your `Podfile`, a `post_install` hook or a build script names the old pod, update the name.
- **Gifu and APNGKit are gone.** Animated images are played by Nuke. If your app depended on those pods only through TurboImage, they disappear from `Podfile.lock`.
- **Nuke is vendored** as prebuilt `Nuke.xcframework` and `NukeUI.xcframework` inside the package (14.0.0), so there is nothing extra to add to the `Podfile`.

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

`urlCache` is the only policy that honours `Cache-Control`, `ETag` and `no-store`, and in 2.0 it does so on Android too (1.x: iOS only). It keeps its own disk store, so a `cacheOnly` load does not see what a `urlCache` load stored on disk, and the reverse. On iOS that store is a 150 MB `URLCache`, which does not keep a response larger than 5% of its size (7.5 MB): such an image is downloaded again whenever it is not in memory. Android has no such limit.

### Lists that reuse views need `recyclingKey`

When `source` changes, 2.0 keeps the previous image on screen until the new one has loaded, so a changed URL swaps without a blank frame. In a list that reuses views (FlashList), that means a reused row would briefly show the previous row's image. Give each image a key that identifies its content:

```diff
  <TurboImage
    source={{ uri: item.avatarUrl }}
+   recyclingKey={item.id}
  />
```

When the key changes together with the source, the view is blanked (or shows its placeholder) first. This is the same contract as expo-image's prop of that name.

### `source` may be a number or a list of sizes

`source` now also accepts a `require()`d asset, and an array of one image at several sizes (see below). Code that keeps sources around to pass to `TurboImage.prefetch` or `dispose`, or reads `.uri` off them, should type them as the exported `Source` (a single source) rather than `TurboImageProps['source']`, which now includes arrays, and narrow before reading `.uri`:

```ts
import type { Source } from 'react-native-turbo-image';

const uri = typeof source === 'number' ? undefined : source.uri;
```

## New in 2.0, optional

### One image at several sizes

Give `source` the sizes your CDN serves, with each file's size in pixels, and the view loads the smallest one it does not have to scale up (expo-image's form):

```tsx
<TurboImage
  source={[
    { uri: 'https://cdn.example.com/p/ada-320.jpg', width: 320, height: 213 },
    { uri: 'https://cdn.example.com/p/ada-1280.jpg', width: 1280, height: 853 },
  ]}
  style={{ width: '100%', aspectRatio: 3 / 2 }}
/>
```

- `cover` and `stretch` pick a size that covers the view, `contain` one that fits it. If none is large enough, the largest. With `resizeMode="center"`, `allowDownscaling={false}`, or before the view has a size, the largest.
- A view that grows past its size later loads the next one up, silently, keeping the image on screen meanwhile (as for `allowDownscaling`). It never switches to a smaller one.
- The first entry's `headers` are sent with every size; other entries' headers are ignored (a development warning says so). `onSuccess.source` is the URL that loaded.

### Prefetching: disk by default, memory at a size

`TurboImage.prefetch` now only downloads by default: no decode and no memory used. A view that shows the image later decodes it from the disk, at the view's size. 1.x also decoded each image into the memory cache at its own size, which no view showing it smaller ever reads: views decode at their own size, under their own memory entries, so a full-size decode only pushed other images out of the cache.

The second argument is now an options object, with the cache policy inside it. 1.x's form, a policy string, still works. To have views find the image in memory, prefetch at their `resize`:

```ts
// For <TurboImage source={source} resize={120} />:
TurboImage.prefetch(thumbnailSources, { resize: 120 });
// 1.x's form, still accepted:
TurboImage.prefetch(sources, 'urlCache');
// The same with options:
TurboImage.prefetch(sources, { cachePolicy: 'urlCache', resize: 120 });
// For a full-screen viewer with allowDownscaling={false}:
TurboImage.prefetch(nextPhotos, { resize: 'original' });
```

`resize` decodes into memory at that width, the same as the views with that `resize` prop, so they decode nothing. It only serves views with exactly that `resize`, no other processing (`blur`, `tint`, `monochrome`) and `allowDownscaling` left on; other views still get the disk copy. A view without `resize` decodes at its laid-out size, which a prefetch cannot predict to the pixel, so it is not offered.

`resize: 'original'` keeps 1.x's full-size decode. Only views that show the image at its own size use it: `allowDownscaling={false}`, `resizeMode="center"`, and `blur` without `resize`.

Under `cachePolicy="memoryOnly"`, and for a local file, there is no disk tier, so the default loads into memory at full size, as 1.x did. If you replaced the loader, your adapter's `prefetch` / `prefetchRequest:completion:` sees the memory write turned off for a prefetch without `resize` and should store the bytes without decoding them; a `resize` prefetch reaches it as a view's request does.

### An image's size before rendering

`TurboImage.getSize(source)` resolves the image's own size in pixels, with its EXIF orientation applied, like React Native's `Image.getSize`:

```ts
const { width, height } = await TurboImage.getSize({ uri: photoUrl });
```

It loads the image into the caches like `prefetch`, but reads the size from the file's header rather than decoding it, so the view that shows it next loads from the disk. An SVG reports its canvas at the screen's pixel ratio. It rejects with `onFailure`'s codes. If you replaced the loader (`TurboImageLoaders.set` on Android, `TIImageLoaderRegistry.sharedLoader` on iOS), `getSize` rejects with `unknown` until your adapter implements `imageSize` / `imageSizeForRequest:completion:`.

### Cache sizes

`TurboImage.configureCache` sizes the caches, in bytes, with expo-image's names. Call it once at startup, in your entry file, before the first image renders and before any other `TurboImage` call (`prefetch`, `getSize` and the rest build the caches too):

```ts
TurboImage.configureCache({ maxDiskSize: 300 * 1024 * 1024 });
```

- It is synchronous: it has taken effect when it returns. It returns `false`, and warns in development, if the caches already exist; they cannot be resized once built.
- `maxDiskSize` (default 150 MB) sizes the disk cache every policy but `urlCache` uses. On Android the `urlCache` policy's HTTP responses share it; on iOS they live in a store of their own, which keeps its 150 MB.
- `maxMemoryCost` sizes decoded images in memory. The default scales with the device (a quarter of the app's memory on Android, Nuke's default on iOS); a fixed size that suits a large phone can strain a small one, so set it only when you have measured.

### Positioning the image, and `scale-down`

`contentPosition` places an image that does not fill its view exactly (expo-image's prop, CSS `object-position`): where a `cover` crop is taken from, or where `contain`, `center` and `scale-down` put the image in the free space. It takes keywords or percentages from an edge:

```tsx
<TurboImage source={{ uri: portraitUrl }} resizeMode="cover" contentPosition="top" />
<TurboImage source={{ uri: logoUrl }} resizeMode="contain" contentPosition={{ left: '0%', bottom: '10%' }} />
```

Point offsets (`{ top: 10 }`) are not supported yet. `resizeMode="scale-down"` draws the image at its own size when it fits and as `contain` when it does not.

### An image as the placeholder

`placeholder` also takes an image, as `{ uri }` or `require('./thumb.jpg')`, typically a small thumbnail already in the cache from a list:

```tsx
<TurboImage source={{ uri: fullUrl }} placeholder={{ uri: thumbnailUrl }} />
```

It loads with the source's headers, unprocessed, and without events of its own, and it is never shown over the loaded image. As with a blurhash, it is removed if the image fails, unless `showPlaceholderOnFailure` is set.

If you replaced the Android loader with `TurboImageLoaders.set`, your adapter shows no image placeholders until it implements `ImageLoaderAdapter.loadPlaceholder` (the default reports none).

## 4. Behaviour that changed

Nothing here needs a code change to compile, but each can change what your app does.

### Sizes and memory

- **Images are decoded no larger than their view.** A 12 MP photo in a thumbnail costs the thumbnail's memory. `onSuccess` therefore reports the decoded size, not the source's.
- A view whose layout grows after its image loaded (a rotation, a card that expands) gets a sharper copy once it has grown by half, with no events and no flash. A zoom by `transform` does not change the layout, so a zoomable image still shows the smaller decode scaled up: set `allowDownscaling={false}` for it.
- Downscaling is not applied with `resizeMode="center"` or with `blur` without `resize`.
- **iOS: `resizeMode="center"` draws a photo at the same size as Android.** It used to draw its pixels as points, so a 600 px image was 600 points wide on iOS and 600 px (228 dp on a 2.6x screen) on Android. Both now use the image's pixels over the screen scale. SVGs are unchanged: their canvas is already in points.

### Events

- `onFailure` gains `code`: `'invalidRequest' | 'notCached' | 'network' | 'decode' | 'unknown'`, the same on both platforms. Branch on `code`; the `error` text is diagnostic and differs between platforms.
- An image with no source, or an empty `uri`, fails with `invalidRequest` as soon as it is mounted. If you render `<TurboImage>` before the URL is known, render it conditionally or expect that event.
- `onCompletion` can report `state: 'cancelled'` when a load is superseded by a newer one. A cancelled load reports neither success nor failure. Every `onStart` is answered by exactly one `onCompletion`.
- `onProgress` is throttled to about 100 events per load.

### Placeholders, fade and the indicator

- `fadeDuration` defaults to 300 ms on Android too (1.x Android: 100 ms). Set `fadeDuration={100}` to keep the old timing.
- The fade now also runs from a placeholder to the image. 1.x forced it to 0 there; set `fadeDuration={0}` to keep that. Memory-cache hits never fade.
- Passing more than one placeholder kind throws in development only. In release builds native picks one; 1.x threw in every build.
- `showPlaceholderOnFailure` without a `placeholder` does nothing. 1.x threw.
- `placeholder.memoryCacheKey` accepts either the URI or the explicit `cacheKey` the other image was loaded with.
- `indicator` appears only for loads that take longer than 150 ms, so cache hits never flash it, and it is never shown together with a `placeholder`.

### Borders and padding

- Border styles on `<TurboImage>` (`borderWidth`, `borderColor`, `borderStyle`, `borderRadius`, also per edge and per corner) now draw on Android. 1.x ignored them there.
- A `borderRadius` in the style clips the image and its placeholder on both platforms. On iOS 1.x needed `overflow: 'hidden'` for that; it is now the default, and `overflow: 'visible'` in your style turns it off.
- On Android the image is laid out inside the border and the `padding` style, as on iOS. 1.x Android ignored `padding`.

### `rounded`, `indicator` and `ref`

1.x always wrapped the image in a container view. 2.0 adds one only for `indicator`, whose spinner is a second view over the image. `rounded` is a style on the image view, which clips itself.

- `ref` is the outermost view either way (the one that has `style`), so measuring works as before.
- `testID`, accessibility props and `onLayout` go to the image view, as in 1.x. With a container that is the inner view.
- Switching `indicator` on or off for a mounted image adds or removes the container, which remounts the image view and restarts its load. If you toggle it at runtime, keep it set instead. Toggling `rounded` does not remount.

### Caching and the network

- `Cache-Control` headers are ignored except under `cachePolicy="urlCache"`.
- `TurboImage.prefetch` resolves `false` when any source fails. 1.x always resolved `true`.
- `TurboImage.prefetch` only downloads unless asked to decode; see [Prefetching](#prefetching-disk-by-default-memory-at-a-size).
- `TurboImage.dispose` now removes the image from memory and disk. It did nothing in 1.x.
- On Android, `dispose` and `clearDiskCache` reject with code `disk` if the disk cache cannot be written to.
- Scheme and host are lower-cased and the `#fragment` is dropped when a URL becomes a cache key, so `HTTPS://CDN.example.com/a.png#x` and `https://cdn.example.com/a.png` share one entry. An explicit `cacheKey` is used as written.
- `source.headers` are sent with the request but are not part of the cache key. A header with CR, LF or NUL in its value, or a name that is not an HTTP token, fails the load with `invalidRequest`.
- Local sources (`file://`, `content://`, `android.resource://`, `require()`) are never copied into the disk cache, and `cacheOnly` does not block them.
- On Android, requests send a descriptive `User-Agent` (`<App>/<version> TurboImage/<version> (Android <release>)`) instead of OkHttp's default, which some CDNs refuse.
- Cookies are unchanged from 1.x: iOS sends the shared `HTTPCookieStorage`'s cookies (those `fetch` set) with image requests, Android sends none. To authorise an image on both platforms, use a signed URL or put the session in `source.headers` (a `Cookie` or `Authorization` header). A cached image outlives the session, so clear the caches on logout either way.

### Processors

- `resize`, `blur`, `monochrome` and `tint` are now one cross-platform implementation, so results differ slightly from 1.x on both platforms.
- `blur` is a Gaussian σ in pixels of the (resized) image. On Android it now applies at the original size, not the view's, so the same value looks weaker on a large photo. Pair it with `resize`.
- You no longer need `resize` only to avoid decoding a large image into a small view: every view now decodes at its own size. On its own it adds a separate cache entry for the same picture. Keep it with `blur`, where it is what keeps the blur small and cheap, to share one bitmap between views of different sizes, or to bound the decode under `allowDownscaling={false}`.
- A `monochrome` colour's alpha is now the effect's intensity.
- A response that is not an image (an HTML error page sent with `200`) fails with `code: 'decode'` on both platforms.
- Processors on an animated image produce a static image on iOS too. 1.x iOS ignored the processors and animated the raw data.

### Formats

- `format` is ignored: GIF, APNG, animated WebP and SVG are detected from the bytes. You can delete the prop.
- `isProgressiveImageRenderingEnabled` is ignored. It had no effect in 1.x either.
- On iOS an animation shows its first frame while Reduce Motion is on or Auto-Play Animated Images is off (Settings › Accessibility › Motion). Animations loop for as long as they are shown, on both platforms.
- On iOS, images are no longer inverted by Smart Invert.

## 5. SVG on iOS and App Review

2.0 renders SVG on iOS the way 1.x did: through Apple's CoreSVG framework, which is private. The functions are looked up at run time (`dlsym`), so if a future iOS removes them, an SVG fails to load (`onFailure` with `code: 'decode'`) instead of crashing the app.

This is the same technique [SDWebImageSVGCoder](https://github.com/SDWebImage/SDWebImageSVGCoder) uses, and its maintainers report having shipped App Store apps with it. It is still private-API use, and Apple could flag it in review. If that risk is not acceptable for your app, do not load SVG through TurboImage on iOS: convert the assets to PDF or PNG, or render them with a library such as react-native-svg.

Android uses `coil-svg` and has no such concern.

## 6. Checklist

- [ ] App is on the New Architecture, React Native 0.88+, Kotlin 2.3+, iOS 16.0+ (deployment target raised in the `Podfile` and in Xcode)
- [ ] `Podfile` and scripts no longer name the `react-native-turbo-image` pod
- [ ] `cachePolicy="dataCache"` replaced with `"default"`
- [ ] Images in recycled lists have a `recyclingKey`
- [ ] Code that reads `source.uri` handles a numeric source
- [ ] `onFailure` handlers branch on `code`
- [ ] Zoomable or growing images set `allowDownscaling={false}`
- [ ] `format` and `isProgressiveImageRenderingEnabled` removed
- [ ] You have decided whether SVG through CoreSVG is acceptable on iOS
