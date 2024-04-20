import React from 'react';
import {
  requireNativeComponent,
  processColor,
  type ProcessedColorValue,
} from 'react-native';
import type { TurboImageProps } from './TurboImage';

const ComponentName = 'TurboImageView';
interface Props extends Omit<TurboImageProps, 'monochrome'> {
  monochrome?: ProcessedColorValue | null;
}
const NativeImage = requireNativeComponent<Props>(ComponentName);

const TurboImage = ({ monochrome, ...props }: TurboImageProps) => {
  return <NativeImage {...props} monochrome={processColor(monochrome)} />;
};

export default TurboImage;
