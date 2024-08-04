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

## Props

### `source`

- **remote image**

  Type: `object`

  - `uri`: Remote url to load the image from.
  - `headers?`: Headers to load the image with. e.g. `{ Authorization: 'someAuthToken' }`

- **local asset**

  Type: `number`, opaque type returned by something like `require('./image.jpg')`

### `style`

Type: `ImageStyle`

### `placeholder`

- Type: `object`
- show placeholder while loading, either `thumbhash` or `blurhash`

```ts
type Placeholder = {
  blurhash: string;
  thumbhash: string;
};
```

### `cachePolicy`

- `memory`: LRU memory cache for processed images. set by default
- `dataCache`: aggressive LRU disk cache
- `urlCache`: HTTP disk cache, respect cache-control

### `resizeMode`

- `contain` (default)
- `cover`
- `stretch`
- `center`

### `indicator`

Type: `object`

- `style?`: `medium` or `large`, default value `medium`.

- `color?`: number / ColorValue

### `showPlaceholderOnFailure`

- Type: `boolean`
- Show the blur placeholder image in the case of a failure.

### `fadeDuration`

- Type: `number`
- The transition duration of the image. default value: 300 milliseconds(iOS) / 100(Android) milliseconds
  > note: To avoid flicking, it will be set to 0 when a placeholder is provided.

### `rounded`

- Type: `boolean`
  Round the image into a circle

### `blur`

- Type: `number`
- The blur radius of the blur filter added to the image

### `monochrome`

- Type: `number / ColorValue`
- The color applied to the image.

> note: For iOS and Android Q+, it works with any color. For Android Q-, it only supports grayscale.

### `resize`

- Type: `number`
- Scales an image to the given width preserving aspect ratio

### `tint`

- Type: `number / ColorValue`
- The color is applied to every non-transparent pixel, causing the image’s shape to adopt that color. This effect is not applied to placeholders.

### `enableLiveTextInteraction` (iOS 16+ only)

- Type: `boolean`
- Enables Live Text interaction with the image.

### `allowHardware` (Android only)

- Type: `boolean`
- Setting this to false this will reduce performance on API 26 and above. Only disable this if necessary. [Coil's docs](https://coil-kt.github.io/coil/recipes/#shared-element-transitions)

### `format`

- Type: `string`
- Specify the format for special image, e.g. `svg`, `gif` and `apng`. In general, TurboImage will determine the decoder automatically.

### `onStart`

The function to call when the image is fetching

### `onSuccess`

The function to call when the image is successfully loaded

### `onFailure`

The function to call when the request failed

### `onCompletion`

The function to call when the request is completed

## Methods

### `prefetch`

```ts
TurboImage.prefetch([URLs]);
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
