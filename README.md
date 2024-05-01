<p align="center">
  <video src="https://github.com/duguyihou/react-native-turbo-image/assets/9347790/719cd0f9-502b-4a9e-9e86-00c97651aca1"  />
</p>
    
> You can find more examples in [example folder](https://github.com/duguyihou/react-native-turbo-image/tree/main/example)

# react-native-turbo-image

Performant React Native image component. Powered by [Nuke](https://github.com/kean/Nuke) and [Coil](https://github.com/coil-kt/coil)

## Features

- Memory and Disk Cache
- Image Processing & Decompression
- Written in TypeScript, Swift and Kotlin
- Support SVG and Gif

## Installation

```sh
npm install react-native-turbo-image
```

## Usage

```js
import TurboImage from 'react-native-turbo-image';

// ...

<TurboImage
  src={url}
  style={{ width: 200, height: 200 }}
  cachePolicy="dataCache"
  blurhash="HSAH_STRING"
/>;
```

## Props

| Prop                             | Type                 | Default                 | Description                                                                    |
| -------------------------------- | -------------------- | ----------------------- | ------------------------------------------------------------------------------ |
| src                              | string(required)     |                         | The URL of the image                                                           |
| style                            | ImageStyle(required) |                         | The style of the image                                                         |
| blurhash                         | string               | undefined               | The blurhash of the image to show while loading [blurh.sh](https://blurha.sh/) |
| cachePolicy                      | string               | memory                  | The cache policy of the image                                                  |
| resizeMode                       | string               | contain                 | The resize mode of the image                                                   |
| showActivityIndicator (iOS only) | boolean              | false                   | Whether to show the indicator when loading                                     |
| fadeDuration                     | number               | 0.3(iOS) / 0.1(Android) | The transition duration of the image                                           |
| borderRadius                     | number               | undefined               | The border radius added to the image                                           |
| rounded                          | boolean              | false                   | Round the image into a circle                                                  |
| blur                             | number               | undefined               | The blur radius of the blur filter added to the image                          |
| monochrome                       | number / ColorValue  | undefined               | The color applied to the image                                                 |
| resize                           | number[]             | undefined               | The size applied to the image                                                  |
| onStart                          | function             | undefined               | The function to call when the image is fetching                                |
| onSucess                         | function             | undefined               | The function to call when the image is successfully loaded                     |
| onFailure                        | function             | undefined               | The function to call when the image is not fetched successfully                |

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
