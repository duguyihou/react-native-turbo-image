import React from 'react';
import { requireNativeComponent, NativeModules } from 'react-native';
import type { TurboImageProps } from './TurboImage';

const { TurboImageViewManager } = NativeModules;
const ComponentName = 'TurboImageView';

const TurboImageView = requireNativeComponent<TurboImageProps>(ComponentName);

// TODO: 🐵 ref
const TurboImage = (props: TurboImageProps) => {
  return <TurboImageView {...props} />;
};

TurboImage.prefetch = async (urls: string[]) => {
  return await TurboImageViewManager.prefetch(urls);
};
TurboImage.clearAllCache = async () => {
  return await TurboImageViewManager.clearAllCache();
};
TurboImage.clearMemoryCache = async () => {
  return await TurboImageViewManager.clearMemoryCache();
};
TurboImage.clearDiskCache = async () => {
  return await TurboImageViewManager.clearDiskCache();
};

export default TurboImage;
