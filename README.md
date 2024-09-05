<div align="center">
  <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/ios.gif" width="200" />
  
  > You can find more examples in [example folder](https://github.com/duguyihou/react-native-turbo-image/tree/main/example)
</div>

# react-native-turbo-image

Performant image Component for React Native. Powered by [Nuke](https://github.com/kean/Nuke) and [Coil](https://github.com/coil-kt/coil)

## Features

- Support New Architecture. see the [example](https://github.com/duguyihou/APPLibTest)
- Support authorization headers
- Support thumbhash, blurhash and memoryCacheKey for placeholder
- Memory cache, aggressive LRU disk cache and HTTP disk cache
- Prefetch, cleanMemoryCache and cleanDiskCache
- Written in TypeScript, Swift and Kotlin
- Support special formats for remote urls (SVG, Gif, APNG)

## Installation

```sh
npm install react-native-turbo-image

cd ios && pod install
```

## Usage

```ts
import TurboImage from 'react-native-turbo-image';

// remote image

<TurboImage
  source={{ uri: "https://placedog.net/300/300?id=1" }}
  style={{ width: 300, height: 300 }}
  cachePolicy="dataCache"
/>;

// local asset

<TurboImage
  source={require('../../assets/local.png')}
  style={{ width: 300, height: 300 }}
/>;

```

## Properties

| Name                        | Type                                                                                                  | Description                                                                                                                                                                                              | Default                 |
| --------------------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `source`                    | [`Source`](https://github.com/duguyihou/react-native-turbo-image?tab=readme-ov-file#source)           | (**Required**) an object containing a `uri` string                                                                                                                                                       | -                       |
| `style`                     | `ImageStyle`                                                                                          | Styles to be applied to the image.                                                                                                                                                                       | -                       |
| `placeholder`               | [`Placeholder`](https://github.com/duguyihou/react-native-turbo-image?tab=readme-ov-file#placeholder) | show placeholder while loading                                                                                                                                                                           | -                       |
| `cachePolicy`               | [`CachePolicy`](https://github.com/duguyihou/react-native-turbo-image?tab=readme-ov-file#cachepolicy) | Determines how to cache the image                                                                                                                                                                        | urlCache                |
| `resizeMode`                | `String`                                                                                              | Resize the image with one of the options: `contain`&nbsp;`cover`&nbsp;`stretch`&nbsp;`center`                                                                                                            | contain                 |
| `indicator`                 | `object`                                                                                              | `style`: `medium`(default) or `large`.&nbsp; `color`: `number / ColorValue`                                                                                                                              | -                       |
| `fadeDuration`              | `number`                                                                                              | The transition duration of the image. Note: To avoid flicking, it will be set to 0 when a placeholder is provided                                                                                        | 300(iOS) / 100(Android) |
| `resize`                    | `number`                                                                                              | Scales an image to the given width preserving aspect ratio                                                                                                                                               | -                       |
| `blur`                      | `number`                                                                                              | The blur radius of the blur filter added to the image                                                                                                                                                    | -                       |
| `monochrome`                | `number / ColorValue`                                                                                 | The color applied to the image. note: For iOS and Android Q+, it works with any color. For Android Q-, it only supports grayscale                                                                        | -                       |
| `tint`                      | `number / ColorValue`                                                                                 | The color is applied to every non-transparent pixel, causing the image’s shape to adopt that color. This effect is not applied to placeholders                                                           | -                       |
| `showPlaceholderOnFailure`  | `boolean`                                                                                             | Show the placeholder image in the case of a failure                                                                                                                                                      | false                   |
| `rounded`                   | `boolean`                                                                                             | Round the image into a circle                                                                                                                                                                            | false                   |
| `enableLiveTextInteraction` | `boolean`                                                                                             | Enables Live Text interaction with the image (iOS 16+ only)                                                                                                                                              | false                   |
| `allowHardware`             | `boolean`                                                                                             | Setting this to false this will reduce performance on API 26 and above. Only disable this if necessary. [Coil's docs](https://coil-kt.github.io/coil/recipes/#shared-element-transitions) (Android only) | false                   |
| `format`                    | `string`                                                                                              | Specify the format for special image, e.g. `svg`, `gif` and `apng`. In general, TurboImage will determine the decoder automatically.                                                                     | -                       |
| `onStart`                   | `Function`                                                                                            | The function to call when the image is fetching.                                                                                                                                                         | -                       |
| `onSuccess`                 | `Function`                                                                                            | The function to call when the image is successfully loaded                                                                                                                                               | -                       |
| `onFailure`                 | `Function`                                                                                            | The function to call when the request failed                                                                                                                                                             | -                       |
| `onCompletion`              | `Function`                                                                                            | The function to call when the request is completed                                                                                                                                                       | -                       |


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

MIT
