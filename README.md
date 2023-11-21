[![Watch the video](https://github.com/duguyihou/react-native-turbo-image/assets/9347790/96d180db-2129-4b61-a59a-c91db6218057)](https://github.com/duguyihou/react-native-turbo-image/assets/9347790/80e97f77-e6bd-4941-bb23-429a04f11af4)

# react-native-turbo-image

Performant React Native image component. Powered by [Kingfisher](https://github.com/onevcat/Kingfisher) and [Coil](https://github.com/coil-kt/coil)

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
    base64Placeholder={base64Placeholder}
/>
```

## Props

| Prop                      | Type     | Default | Description                                                                                          |
| ------------------------- | -------- | ------- | ---------------------------------------------------------------------------------------------------- |
| url                       | string   |         | The URL of the image                                                                                 |
| style                     | object   |         | The style of the image                                                                               |
| resizeMode                | string   | contain | The resize mode of the image                                                                         |
| showActivityIndicator     | boolean  | false   | Whether to show the UIActivityIndicatorView indicator when the image is loading                      |
| base64Placeholder         | string   |         | The base64 encoded placeholder image to show while the image is loading                              |
| cachePolicy               | string   | shared  | The cache policy of the image                                                                        |
| fadeDuration              | number   | 0.5     | The transition duration of the image                                                                 |
| rounded                   | boolean  | false   | Round the image into a circle                                                                        |
| onError                   | function |         | The function to call when an error occurs.                                                           |
| onSucess                  | function |         | The function to call when the image is successfully loaded                                           |

## Contributing

See the [contributing guide](CONTRIBUTING.md) to learn how to contribute to the repository and the development workflow.

## License

MIT
