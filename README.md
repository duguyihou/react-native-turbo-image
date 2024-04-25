<p align="center">
  <video src="https://github.com/duguyihou/react-native-turbo-image/assets/9347790/da98c785-e7dd-48f8-bad2-17d7a5bac330"  />
</p>

# react-native-turbo-image

Performant React Native image component. Powered by [Nuke](https://github.com/kean/Nuke) and [Coil](https://github.com/coil-kt/coil)

## Features

- Image downloading, caching and processing
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
  blurhash="hashString encoded by blurehash"
/>;
```

## Props

| Prop                             | Type                | Default                 | Description                                                |
| -------------------------------- | ------------------- | ----------------------- | ---------------------------------------------------------- |
| src                              | string(required)    |                         | The URL of the image                                       |
| style                            | ImageStyle(required)|                         | The style of the image                                     |
| resizeMode                       | string              | contain                 | The resize mode of the image                               |
| showActivityIndicator (iOS only) | boolean             | false                   | Whether to show the indicator when loading                 |
| fadeDuration                     | number              | 0.3(iOS) / 0.1(Android) | The transition duration of the image                       |
| borderRadius                     | number              | undefined               | The border radius added to the image                       |
| rounded                          | boolean             | false                   | Round the image into a circle                              |
| blur                             | number              | undefined               | The blur radius of the blur filter added to the image      |
| monochrome                       | number / ColorValue | undefined               | The color applied to the image                             |
| blurhash                         | string              | undefined               | The blurhash of the image to show while loading [blurh.sh](https://blurha.sh/)            |
| cachePolicy                      | string              | memory                  | The cache policy of the image                              |
| onSucess                         | function            | undefined               | The function to call when the image is successfully loaded |
| onFailure                        | function            | undefined               | The function to call when the image is not fetched successfully                |

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
