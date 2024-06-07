import React from 'react';
import {
  requireNativeComponent,
  NativeModules,
  type ProcessedColorValue,
  processColor,
} from 'react-native';
import type { IndicatorStyle, TurboImageApi, TurboImageProps } from './types';

const { TurboImageViewManager } = NativeModules;
const ComponentName = 'TurboImageView';
interface Props
  extends Omit<TurboImageProps, 'monochrome' | 'tint' | 'indicator'> {
  monochrome?: ProcessedColorValue | null;
  indicator?: Partial<{
    style: IndicatorStyle;
    color: ProcessedColorValue | null;
  }>;
  tint?: ProcessedColorValue | null;
}
const NativeImage = requireNativeComponent<Props>(ComponentName);

const TurboImage = (props: TurboImageProps) => {
  const {
    cachePolicy,
    resizeMode,
    indicator,
    placeholder,
    fadeDuration,
    borderRadius,
    rounded,
    blur,
    monochrome,
    resize,
    tint,
    isSVG,
    isGif,
    onStart,
    onSuccess,
    onFailure,
    onCompletion,
    ...restProps
  } = props;
  return (
    <NativeImage
      {...restProps}
      cachePolicy={cachePolicy}
      resizeMode={resizeMode}
      indicator={{
        style: indicator?.style,
        color: processColor(indicator?.color),
      }}
      placeholder={placeholder}
      fadeDuration={fadeDuration}
      borderRadius={borderRadius}
      rounded={rounded}
      blur={blur}
      monochrome={processColor(monochrome)}
      resize={resize}
      tint={processColor(tint)}
      isSVG={isSVG}
      isGif={isGif}
      onStart={onStart}
      onSuccess={onSuccess}
      onFailure={onFailure}
      onCompletion={onCompletion}
    />
  );
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

export default TurboImage as React.FC<TurboImageProps> & TurboImageApi;
