| grid | image processing |
|---|---|
| <img src="https://github.com/duguyihou/react-native-turbo-image/assets/9347790/2655214f-f63d-4102-8df2-d82afc1f5d19" width="300" height="600"/>  |  <img src="https://github.com/duguyihou/react-native-turbo-image/assets/9347790/6cfce7c3-8b75-4de9-b9ce-35b8e435d39d" width="300" height="600"/>   |

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
