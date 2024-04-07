import React from 'react';
import { requireNativeComponent } from 'react-native';
import type { TurboImageProps } from './TurboImage';

const ComponentName = 'TurboImageView';

const NativeImage = requireNativeComponent<TurboImageProps>(ComponentName);

const TurboImage = (props: TurboImageProps) => {
  return <NativeImage {...props} />;
};

export default TurboImage;
