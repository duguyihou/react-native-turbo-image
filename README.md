<div align="center">
  <h1>TurboImage</h1>
  <a href="https://www.npmjs.com/package/react-native-turbo-image">
    <img src="https://img.shields.io/npm/v/react-native-turbo-image.svg" alt="package version" />
  </a>
  <a href="https://www.npmjs.com/package/react-native-turbo-image">
    <img src="https://img.shields.io/npm/dm/react-native-turbo-image" alt="npm downloads" />
  </a>
</div>
<div align="center">
  <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/ios.gif" width="200" />

> You can find more examples in [example folder](https://github.com/duguyihou/react-native-turbo-image/tree/main/example)

</div>

Performant image component for React Native. Powered by [Nuke](https://github.com/kean/Nuke) and [Coil](https://github.com/coil-kt/coil)

## Features

- Support New Architecture. see the [example](https://github.com/duguyihou/APPLibTest)
- Support authorization headers
- Support thumbhash, blurhash and memoryCacheKey for placeholder
- Memory cache, aggressive LRU disk cache and HTTP disk cache
- Prefetch, dispose, cleanMemoryCache and cleanDiskCache
- Written in TypeScript, Swift and Kotlin
- Support special formats (SVG, Gif, APNG)

## Benchmarks

>Disclaimer: Benchmark results are based on controlled testing environments and may vary in real-world applications depending on factors such as network conditions, device specifications, image sizes, and concurrent tasks.

For example, loading 120 images in flatlist. See the code in the example folder:

With [React Native built-in image](https://github.com/duguyihou/react-native-turbo-image/blob/main/example/src/screens/list/ImageScreen.tsx) 🐢:
```
took 15s
```

With [react-native-turbo-image](https://github.com/duguyihou/react-native-turbo-image/blob/main/example/src/screens/list/DataCacheScreen.tsx) ⚡️:
```
took 2s
```

## Installation

```sh
npm install react-native-turbo-image

cd ios && pod install
```

## Usage

```ts
import TurboImage from 'react-native-turbo-image';

<TurboImage
  source={{ uri: "https://cloud.githubusercontent.com/assets/1567433/9781817/ecb16e82-57a0-11e5-9b43-6b4f52659997.jpg" }}
  cachePolicy="urlCache"
  style={{ width: 240, height: 360 }}
/>;

```

## Properties

| Name                                 | Type                                                                                                  | Description                                                                                                                                                                                           | Default                 |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `source`                             | [`Source`](https://github.com/duguyihou/react-native-turbo-image?tab=readme-ov-file#source)           | (**Required**) an object containing a `uri` string                                                                                                                                                    | -                       |
| `style`                              | `ImageStyle`                                                                                          | Styles to be applied to the image.                                                                                                                                                                    | -                       |
| `placeholder`                        | [`Placeholder`](https://github.com/duguyihou/react-native-turbo-image?tab=readme-ov-file#placeholder) | show placeholder while loading                                                                                                                                                                        | -                       |
| `cachePolicy`                        | [`CachePolicy`](https://github.com/duguyihou/react-native-turbo-image?tab=readme-ov-file#cachepolicy) | Determines how to cache the image                                                                                                                                                                     | urlCache                |
| `resizeMode`                         | `String`                                                                                              | Resize the image with one of the options: `contain`&nbsp;`cover`&nbsp;`stretch`&nbsp;`center`                                                                                                         | contain                 |
| `indicator`                          | `object`                                                                                              | `style`: `medium`(default) or `large`.&nbsp; `color`: `number / ColorValue`                                                                                                                           | -                       |
| `fadeDuration`                       | `number`                                                                                              | The transition duration of the image. Note: To avoid flicking, it will be set to 0 when a placeholder is provided                                                                                     | 300(iOS) / 100(Android) |
| `resize`                             | `number`                                                                                              | Scales an image to the given width preserving aspect ratio                                                                                                                                            | -                       |
| `blur`                               | `number`                                                                                              | The blur radius of the blur filter added to the image                                                                                                                                                 | -                       |
| `monochrome`                         | `number / ColorValue`                                                                                 | The color applied to the image. note: For iOS and Android Q+, it works with any color. For Android Q-, it only supports grayscale                                                                     | -                       |
| `tint`                               | `number / ColorValue`                                                                                 | The color is applied to every non-transparent pixel, causing the image’s shape to adopt that color. This effect is not applied to placeholders                                                        | -                       |
| `showPlaceholderOnFailure`           | `boolean`                                                                                             | Show the placeholder image in the case of a failure                                                                                                                                                   | false                   |
| `rounded`                            | `boolean`                                                                                             | Round the image into a circle                                                                                                                                                                         | false                   |
| `enableLiveTextInteraction`          | `boolean`                                                                                             | Enables Live Text interaction with the image (iOS 16+ only)                                                                                                                                           | false                   |
| `allowHardware`                      | `boolean`                                                                                             | Setting this to `false` will reduce performance on API 26 and above. Only disable this if necessary. [Coil's docs](https://coil-kt.github.io/coil/recipes/#shared-element-transitions) (Android only) | true                    |
| `isProgressiveImageRenderingEnabled` | `boolean`                                                                                             | If disabled, progressive image scans will be ignored (iOS only)                                                                                                                                       | true                    |
| `format`                             | `string`                                                                                              | Specify the format for special image, e.g. `svg`, `gif` and `apng`. In general, TurboImage will determine the decoder automatically.                                                                  | -                       |
| `onStart`                            | `Function`                                                                                            | Gets called when the request is started.                                                                                                                                                              | -                       |
| `onProgress`                         | `Function`                                                                                            | Gets called when the request progress is updated.                                                                                                                                                     | -                       |
| `onSuccess`                          | `Function`                                                                                            | Gets called when the requests finished successfully.                                                                                                                                                  | -                       |
| `onFailure`                          | `Function`                                                                                            | Gets called when the requests fails.                                                                                                                                                                  | -                       |
| `onCompletion`                       | `Function`                                                                                            | Gets called when the request is completed.                                                                                                                                                            | -                       |

## Methods

### `prefetch`

```ts
await TurboImage.prefetch([Source]);
```

### `dispose`

```ts
await TurboImage.dispose([Source]);
```

### `clearMemoryCache`

```ts
await TurboImage.clearMemoryCache();
```

### `clearDiskCache`

```ts
await TurboImage.clearDiskCache();
```

## Types

### Source

| Name       | Type                     | Description                                                                                                       |
| ---------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `uri`      | `string`                 | the url of the image                                                                                              |
| `headers`  | `Record<string, string>` | An object representing the HTTP headers to send along with the request for a remote image                         |
| `cacheKey` | `string`                 | The cache key used to query and store this specific image. If not provided, the uri is used also as the cache key |

### Placeholder

| Name             | Type     | Description                                                                                                                                                                       |
| ---------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `thumbhash`      | `string` | A string used to generate the image placeholder. For more information, see [thumbhash](https://evanw.github.io/thumbhash/)                                                        |
| `blurhash`       | `string` | A string used to generate the image placeholder. For more information, see [woltapp/blurhash](https://github.com/woltapp/blurhash).                                               |
| `memoryCacheKey` | `string` | Using the key of previous request as placeholder. For more information, see [Memory Cache Key](https://coil-kt.github.io/coil/recipes/#using-a-memory-cache-key-as-a-placeholder) |

| thumbhash                                                                                                              | blurhash                                                                                                              | memoryCacheKey                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/thumbhash.gif" width="150" /> | <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/blurhash.gif" width="150" /> | <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/memoryCacheKey.gif" width="150" /> |

### CachePolicy

| Name        | Type     | Description                                                                                                                                    |
| ----------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `urlCache`  | `string` | Allows the server to manage caching precisely through cache-control HTTP headers. You can determine which images to cache and caching duration |
| `dataCache` | `string` | Ignores [HTTP cache control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)                                          |

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

TurboImage is released under the [MIT](https://github.com/duguyihou/react-native-turbo-image?tab=MIT-1-ov-file) license. Some of the dependencies are licensed differently, with the Apache-2.0 license, for example.
