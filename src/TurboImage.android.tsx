import React from 'react';
import {
  NativeModules,
  requireNativeComponent,
  processColor,
  type ProcessedColorValue,
} from 'react-native';
import type { TurboImageProps } from './TurboImage';

const { TurboImageViewManager } = NativeModules;
const ComponentName = 'TurboImageView';
interface Props extends Omit<TurboImageProps, 'monochrome'> {
  monochrome?: ProcessedColorValue | null;
}
const NativeImage = requireNativeComponent<Props>(ComponentName);

const TurboImage = ({ monochrome, ...props }: TurboImageProps) => {
  return <NativeImage {...props} monochrome={processColor(monochrome)} />;
};

TurboImage.prefetch = async (sources: string[]) => {
  return await TurboImageViewManager.prefetch(sources);
};

TurboImage.clearMemoryCache = async () => {
  return await TurboImageViewManager.clearMemoryCache();
};
TurboImage.clearDiskCache = async () => {
  return await TurboImageViewManager.clearDiskCache();
};

export default TurboImage;
