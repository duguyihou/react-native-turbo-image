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

TurboImage.prefetch = (urls: string[]) => TurboImageViewManager.prefetch(urls);
TurboImage.clearAllCache = () => TurboImageViewManager.clearAllCache();
TurboImage.clearMemoryCache = () => TurboImageViewManager.clearMemoryCache();
TurboImage.clearDiskCache = () => TurboImageViewManager.clearDiskCache();

export default TurboImage;
