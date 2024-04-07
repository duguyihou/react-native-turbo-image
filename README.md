| grid | image processing |
|---|---|
| [![Watch the video](https://github.com/duguyihou/react-native-turbo-image/assets/9347790/0885c122-226c-40a6-b0eb-6c6e882e330b)](https://github.com/duguyihou/react-native-turbo-image/assets/9347790/030bf80c-98bc-451a-a4ec-7941b01da899)   | [![Watch the video](https://github.com/duguyihou/react-native-turbo-image/assets/9347790/6434207d-fb55-48f7-96ed-14d522247b61)](https://github.com/duguyihou/react-native-turbo-image/assets/9347790/70e6196a-099e-42eb-a203-0ae49cf696ef)  |


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
import TurboImage from "react-native-turbo-image";

// ...

<TurboImage
    url={url}
    style={styles.box}
    showActivityIndicator
    cachePolicy="dataCache"
    blurhash="LMDSzI~pV=RO9ZV@xv%MRPRlxuog"
/>
```

## Props

| Prop                      | Type     | Default | Description                                                                                          |
| ------------------------- | -------- | ------- | ---------------------------------------------------------------------------------------------------- |
| url                       | string   |         | The URL of the image                                                                                 |
| style                     | object   |         | The style of the image                                                                               |
| resizeMode                | string   | contain | The resize mode of the image                                                                         |
| showActivityIndicator     | boolean  | false   | Whether to show the UIActivityIndicatorView indicator when loading                                   |
| base64Placeholder         | string   |         | The base64 encoded placeholder image to show while loading                                           |
| blurhash                  | string   |         | The blurhash of the image to show while loading                                                      | 
| cachePolicy               | string   | memory  | The cache policy of the image                                                                        |
| fadeDuration              | number   | 0.5     | The transition duration of the image                                                                 |
| rounded                   | boolean  | false   | Round the image into a circle                                                                        |
| tintColor                 | string   |         | tint color                                                                                           |
| onError                   | function |         | The function to call when an error occurs.                                                           |
| onSucess                  | function |         | The function to call when the image is successfully loaded                                           |

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
