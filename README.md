<div align="center">
  <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/ios.gif" width="200" />
  
  > You can find more examples in [example folder](https://github.com/duguyihou/react-native-turbo-image/tree/main/example)
</div>

# react-native-turbo-image

Performant image Component for React Native. Powered by [Nuke](https://github.com/kean/Nuke) and [Coil](https://github.com/coil-kt/coil)

## Features

- Support New Architecture. see the [example](https://github.com/duguyihou/APPLibTest)
- Support authorization headers
- Support thumbhash and blurhash for placeholder
- Memory cache, aggressive LRU disk cache and HTTP disk cache
- Prefetch, cleanMemoryCache and cleanDiskCache
- Written in TypeScript, Swift and Kotlin
- Support special formats (SVG, Gif, APNG)

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
  cachePolicy="urlCache"
/>;

// local asset

<TurboImage
  source={require('../../assets/local.png')}
  style={{ width: 300, height: 300 }}
/>;

```

## Paramaters

| Parameter                   | Type                           | Description                                                                                                                                                                                              | Default                 |
| --------------------------- | ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `source`                    | `Object`&nbsp;or&nbsp;`number` | (**Required**) Can be an object containing a `uri` string for remote image or local asset using `require`.                                                                                               | -                       |
| `style`                     | `ImageStyle`                   | Styles to be applied to the image.                                                                                                                                                                       | -                       |
| `placeholder`               | `object`                       | show placeholder while loading, either `thumbhash` or `blurhash`                                                                                                                                         | -                       |
| `cachePolicy`               | `string`                       | `memory`: LRU memory cache for processed images. `dataCache`: aggressive LRU disk cache `urlCache`: HTTP disk cache, respect cache-control                                                               | memory                  |
| `resizeMode`                | `String`                       | Resize the image with one of the options: `contain`&nbsp;`cover`&nbsp;`stretch`&nbsp;`center`                                                                                                            | contain                 |
| `indicator`                 | `object`                       | `style`: `medium`(default) or `large`.&nbsp; `color`: `number / ColorValue`                                                                                                                              | -                       |
| `fadeDuration`              | `number`                       | The transition duration of the image. Note: To avoid flicking, it will be set to 0 when a placeholder is provided                                                                                        | 300(iOS) / 100(Android) |
| `resize`                    | `number`                       | Scales an image to the given width preserving aspect ratio                                                                                                                                               | -                       |
| `blur`                      | `number`                       | The blur radius of the blur filter added to the image                                                                                                                                                    | -                       |
| `monochrome`                | `number / ColorValue`          | The color applied to the image. note: For iOS and Android Q+, it works with any color. For Android Q-, it only supports grayscale                                                                        | -                       |
| `tint`                      | `number / ColorValue`          | The color is applied to every non-transparent pixel, causing the image’s shape to adopt that color. This effect is not applied to placeholders                                                           | -                       |
| `showPlaceholderOnFailure`  | `boolean`                      | Show the blur placeholder image in the case of a failure                                                                                                                                                 | false                   |
| `rounded`                   | `boolean`                      | Round the image into a circle                                                                                                                                                                            | false                   |
| `enableLiveTextInteraction` | `boolean`                      | Enables Live Text interaction with the image (iOS 16+ only)                                                                                                                                              | false                   |
| `allowHardware`             | `boolean`                      | Setting this to false this will reduce performance on API 26 and above. Only disable this if necessary. [Coil's docs](https://coil-kt.github.io/coil/recipes/#shared-element-transitions) (Android only) | false                   |
| `format`                    | `string`                       | Specify the format for special image, e.g. `svg`, `gif` and `apng`. In general, TurboImage will determine the decoder automatically.                                                                     | -                       |
| `onStart`                   | `Function`                     | The function to call when the image is fetching.                                                                                                                                                         | -                       |
| `onSuccess`                 | `Function`                     | The function to call when the image is successfully loaded                                                                                                                                               | -                       |
| `onFailure`                 | `Function`                     | The function to call when the request failed                                                                                                                                                             | -                       |
| `onCompletion`              | `Function`                     | The function to call when the request is completed                                                                                                                                                       | -                       |


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

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
