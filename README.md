<p align="center">
  <video src="https://github.com/duguyihou/react-native-turbo-image/assets/9347790/6458b8b8-f9e9-4fef-84d2-84c9abeb4346"  />
</p>

# react-native-turbo-image

Performant React Native image component. Powered by [Nuke](https://github.com/kean/Nuke) and [Coil](https://github.com/coil-kt/coil)

## Features

- Image downloading and caching
- TypeScript Support
- written in Swift and Kotlin

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
  style={styles.box}
  cachePolicy="dataCache"
  blurhash="ULKKWp^+s,_300M{t7tR~XNHE2bI00xuWBRP"
/>;
```

## Props

| Prop                             | Type                | Default                 | Description                                                |
| -------------------------------- | ------------------- | ----------------------- | ---------------------------------------------------------- |
| src                              | string              |                         | The URL of the image                                       |
| resizeMode                       | string              | contain                 | The resize mode of the image                               |
| showActivityIndicator (iOS only) | boolean             | false                   | Whether to show the indicator when loading                 |
| fadeDuration                     | number              | 0.3(iOS) / 0.1(Android) | The transition duration of the image                       |
| borderRadius                     | number              |                         | The border radius added to the image                       |
| rounded                          | boolean             | false                   | Round the image into a circle                              |
| blur                             | number              |                         | The blur radius of the blur filter added to the image      |
| monochrome                       | number / ColorValue |                         | The color applied to the image                             |
| blurhash                         | string              |                         | The blurhash of the image to show while loading            |
| cachePolicy                      | string              | memory                  | The cache policy of the image                              |
| onError                          | function            |                         | The function to call when an error occurs.                 |
| onSucess                         | function            |                         | The function to call when the image is successfully loaded |

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
