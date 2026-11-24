// One component per library, all with the same props, so every library
// renders the same scenario:
// - `cover` everywhere (thumbnail grids are what we measure).
// - Default caches; cold/warm runs come from the bench script clearing app
//   data, not from each library's cache API. One exception, as a second
//   variant: expo-image's default `cachePolicy` is 'disk', which skips its
//   memory cache on both platforms (ios/ImageView.swift, `cachePolicy =
//   .disk`; ExpoImageViewWrapper.kt, `skipMemoryCache(true)`), while
//   TurboImage's default reads memory first. `expo` measures the default an
//   app gets; `expoMem` sets 'memory-disk', caching like TurboImage, so a
//   difference that only the default explains shows up as such.
// - Default downscaling (on for all three); changing it would measure config.
// - `recyclingKey` where supported, since FlashList reuses views.
// "Loaded" is the library's success event (decoded, not yet drawn).
//
// FastImage is not compared: it and expo-image both ship an `AppGlideModule`
// on Android, and Glide allows one per app.
// TODO: a second APK without expo-image for FastImage runs (its adapter also
// needs a style cast for `width`/`height`).
import { Image as ExpoImage } from 'expo-image';
import type { ImageProps } from 'expo-image';
import type { ComponentType } from 'react';
import { Image as RNImage } from 'react-native';
import { TurboImage } from 'react-native-turbo-image';

export type BenchImageProps = {
  uri: string;
  size: number;
  recyclingKey: string;
  // The library's own "load began" event.
  onStart: () => void;
  onLoad: () => void;
  onError: (message: string) => void;
};

function Turbo({ uri, size, recyclingKey, onStart, onLoad, onError }: BenchImageProps) {
  return (
    <TurboImage
      source={{ uri }}
      style={{ width: size, height: size }}
      resizeMode="cover"
      recyclingKey={recyclingKey}
      onStart={onStart}
      onSuccess={onLoad}
      onFailure={(e) => onError(e.nativeEvent.error)}
    />
  );
}

function Expo({
  uri,
  size,
  recyclingKey,
  onStart,
  onLoad,
  onError,
  cachePolicy,
}: BenchImageProps & { cachePolicy?: ImageProps['cachePolicy'] }) {
  return (
    <ExpoImage
      source={{ uri }}
      cachePolicy={cachePolicy}
      style={{ width: size, height: size }}
      contentFit="cover"
      recyclingKey={recyclingKey}
      onLoadStart={onStart}
      onLoad={onLoad}
      onError={(e) => onError(e.error)}
    />
  );
}

// expo-image with its memory cache on: like-for-like caching with TurboImage.
function ExpoMem(props: BenchImageProps) {
  return <Expo {...props} cachePolicy="memory-disk" />;
}

function Core({ uri, size, onStart, onLoad, onError }: BenchImageProps) {
  return (
    <RNImage
      source={{ uri }}
      style={{ width: size, height: size }}
      resizeMode="cover"
      onLoadStart={onStart}
      onLoad={onLoad}
      onError={(e) => onError(String(e.nativeEvent.error))}
    />
  );
}

// Keys are the `lib` names the deep link and bench script use.
export const LIBRARIES = {
  turbo: Turbo,
  expo: Expo,
  expoMem: ExpoMem,
  rn: Core,
} satisfies Record<string, ComponentType<BenchImageProps>>;

export type LibraryName = keyof typeof LIBRARIES;

export function isLibraryName(name: string | null): name is LibraryName {
  return name !== null && name in LIBRARIES;
}
