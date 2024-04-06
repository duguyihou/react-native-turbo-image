import React from 'react';
import {
  requireNativeComponent,
  NativeModules,
  type ProcessedColorValue,
  processColor,
} from 'react-native';
import { type TurboImageProps } from './TurboImage';

const { TurboImageViewManager } = NativeModules;
const ComponentName = 'TurboImageView';
interface Props extends Omit<TurboImageProps, 'monochrome'> {
  monochrome?: ProcessedColorValue | null;
}
const TurboImageView = requireNativeComponent<Props>(ComponentName);

const TurboImage = ({ monochrome, ...props }: TurboImageProps) => {
  return <TurboImageView {...props} monochrome={processColor(monochrome)} />;
};

TurboImage.prefetch = async (urls: string[]) => {
  return await TurboImageViewManager.prefetch(urls);
};

TurboImage.clearMemoryCache = async () => {
  return await TurboImageViewManager.clearMemoryCache();
};
TurboImage.clearDiskCache = async () => {
  return await TurboImageViewManager.clearDiskCache();
};

export default TurboImage;
