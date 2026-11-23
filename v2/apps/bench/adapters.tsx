// One component per library under test, all with the same props, so a
// scenario renders the same thing whichever library it was launched with.
//
// What "the same" means here, and why:
// - `cover` everywhere: grids of thumbnails are the case the benchmark is
//   about, and every library supports it.
// - Each library's default cache settings (memory + disk). Cold and warm
//   runs are produced by the bench script (clearing app data, or not), not
//   by each library's own cache API, so every library starts from the same
//   state.
// - Downscaling to the view's size is left at each library's default: on
//   for TurboImage and expo-image; RN's <Image> (Fresco) always resizes to
//   the view on Android. Turning it off for some would measure
//   configuration, not libraries.
// - `recyclingKey` for the libraries that have it (TurboImage, expo-image),
//   because FlashList reuses views and both document the key for that case.
//
// "Loaded" is the library's success event: the image is decoded and handed
// to the view. No library reports when the frame showing it is drawn.
//
// Not compared: FastImage (@d11/react-native-fast-image). On Android it and
// expo-image are both built on Glide, and each ships an `AppGlideModule`;
// Glide allows one per app, so the two cannot share an APK (R8: "Type
// com.bumptech.glide.GeneratedAppGlideModuleImpl is defined multiple
// times").
// TODO: a second APK without expo-image for FastImage runs. Its adapter
// also needs a style cast: FastImage 8.13's `ImageStyle` lacks
// `width`/`height` under RN 0.88's types.
import { Image as ExpoImage } from 'expo-image';
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

function Expo({ uri, size, recyclingKey, onStart, onLoad, onError }: BenchImageProps) {
  return (
    <ExpoImage
      source={{ uri }}
      style={{ width: size, height: size }}
      contentFit="cover"
      recyclingKey={recyclingKey}
      onLoadStart={onStart}
      onLoad={onLoad}
      onError={(e) => onError(e.error)}
    />
  );
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

// The `lib` names are what the deep link and the bench script use.
export const LIBRARIES = {
  turbo: Turbo,
  expo: Expo,
  rn: Core,
} satisfies Record<string, ComponentType<BenchImageProps>>;

export type LibraryName = keyof typeof LIBRARIES;

export function isLibraryName(name: string | null): name is LibraryName {
  return name !== null && name in LIBRARIES;
}
