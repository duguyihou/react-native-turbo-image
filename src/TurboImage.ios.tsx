import React from 'react';
import { requireNativeComponent } from 'react-native';
import type { TurboImageProps } from './TurboImage';

const ComponentName = 'TurboImageView';

const TurboImageView = requireNativeComponent<TurboImageProps>(ComponentName);

// TODO: 🐵 ref
const TurboImage = (props: TurboImageProps) => {
  return <TurboImageView {...props} />;
};

export default TurboImage;
