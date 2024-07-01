<div align="center">
  <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/list.gif" width="200" />
  <img src="https://github.com/duguyihou/react-native-turbo-image/blob/main/example/assets/process.gif" width="200" />
  
  > You can find more examples in [example folder](https://github.com/duguyihou/react-native-turbo-image/tree/main/example)
</div>

# react-native-turbo-image

Performant React Native image component. Powered by [Nuke](https://github.com/kean/Nuke) and [Coil](https://github.com/coil-kt/coil)

## Features

- Memory cache, aggressive LRU disk cache and HTTP disk cache
- Image Processing & Decompression
- Written in TypeScript, Swift and Kotlin
- Support special formats
  - SVG
  - Gif
  - APNG

## Installation

```sh
npm install react-native-turbo-image

cd ios && pod install
```

## Usage

```ts
import TurboImage from 'react-native-turbo-image';

// ...

<TurboImage
  source={{ uri: item.url }}
  style={{ width: 200, height: 200 }}
  cachePolicy="urlCache"
/>;
```

## Props

### `source: object`

- `uri`: Remote url to load the image from.
- `headers?`: Headers to load the image with. e.g. `{ Authorization: 'someAuthToken' }`

### `style: ImageStyle`

The style of the image

### `placeholder?: Partial<Placeholder>`

```ts
type Placeholder = {
  blurhash: string;
  thumbhash: string;
};
```

show placeholder while loading, either `thumbhash` or `blurhash`

- [thumbhash](https://evanw.github.io/thumbhash/)
- [blurhash](https://blurha.sh/)

### `cachePolicy?: enum`

The cache policy of the image

- `memory`: LRU memory cache for processed images. set by default
- `dataCache`: aggressive LRU disk cache
- `urlCache`: HTTP disk cache, respect cache-control

### `resizeMode?: enum`

The resize mode of the image, default value `contain`

- `contain`
- `cover`
- `stretch`
- `center`

### `indicator`

show the indicator when loading,

- `style?`: `medium` or `large`, default value `medium`.

- `color?`: number / ColorValue

```ts
indicator={{ style: 'large', color: 'red' }}
```

### `showPlaceholderOnFailure?: boolean`

Show the blur placeholder image in the case of a failure.

### `fadeDuration?: number`

The transition duration of the image. default value: 300(iOS) / 100(Android)

### `borderRadius?: number`

The border radius added to the image

### `rounded?: boolean`

Round the image into a circle

### `blur?: number`

The blur radius of the blur filter added to the image

### `monochrome?: number / ColorValue`

The color applied to the image.

> note: For iOS and Android Q+, it works with any color. For Android Q-, it only supports grayscale.

### `resize?: number`

Scales an image to the given width preserving aspect ratio

### `tint?: number / ColorValue`

The color is applied to every non-transparent pixel, causing the image’s shape to adopt that color. This effect is not applied to placeholders.

### `enableLiveTextInteraction?: boolean` (iOS 16+ only)

Enables Live Text interaction with the image.

### `format?: String`

Specify the format for special image, e.g. `svg` and `gif`. In general, TurboImage will determine the decoder automatically.

### `onStart?: (result: NativeSyntheticEvent<TaskState>) => void`

The function to call when the image is fetching

### `onSuccess?: (result: NativeSyntheticEvent<Success>) => void`

The function to call when the image is successfully loaded

### `onFailure?: (result: NativeSyntheticEvent<Failure>) => void`

The function to call when the request failed

### `onCompletion?: (result: NativeSyntheticEvent<TaskState>) => void`

The function to call when the request is completed

## Methods

### `prefetch: (sources: string[]) => Promise<void>`

```ts
TurboImage.prefetch([URLs]);
```

### `clearMemoryCache: () => Promise<void>`

```ts
await TurboImage.clearMemoryCache();
```

### `clearDiskCache: () => Promise<void>`

```ts
await TurboImage.clearDiskCache();
```

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
