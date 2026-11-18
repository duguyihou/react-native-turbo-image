# react-native-turbo-image

Performant image component for React Native, backed by
[Nuke](https://github.com/kean/Nuke) on iOS and
[Coil](https://github.com/coil-kt/coil) on Android.

> **2.0 is in development.** This is a pre-release of the New
> Architecture-only rewrite, published under the `next` tag. The stable 1.x
> line is what `npm install react-native-turbo-image` gives you.

## Requirements

- React Native 0.88 or newer, New Architecture only
- iOS 15.1 or newer
- Android `minSdk` 24, Kotlin 2.3 or newer

## Installation

```sh
npm install react-native-turbo-image@next
cd ios && pod install
```

The pod is named `TurboImage` (it was `react-native-turbo-image` in 1.x).
Autolinking handles the rename; a `Podfile` that names the pod directly needs
updating.

## Usage

```tsx
import { TurboImage } from 'react-native-turbo-image';

export function Avatar({ uri }: { uri: string }) {
  return (
    <TurboImage
      source={{ uri }}
      style={{ width: 96, height: 96 }}
      resizeMode="cover"
      cachePolicy="default"
      placeholder={{ blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' }}
      onFailure={(event) => console.warn(event.nativeEvent.code)}
    />
  );
}
```

Cache management:

```ts
await TurboImage.prefetch([{ uri: 'https://example.com/photo.jpg' }]);
await TurboImage.dispose([{ uri: 'https://example.com/photo.jpg' }]);
await TurboImage.clearMemoryCache();
await TurboImage.clearDiskCache();
```

## Documentation

- [Architecture and decisions](https://github.com/duguyihou/react-native-turbo-image/blob/main/v2/docs/rfc/0001-turbo-image-2-native-toolchain.md)
- [Migration plan from 1.x](https://github.com/duguyihou/react-native-turbo-image/blob/main/v2/docs/migration-plan.md)
- [Compatibility matrix](https://github.com/duguyihou/react-native-turbo-image/blob/main/v2/docs/compatibility-matrix.md)

## License

MIT
