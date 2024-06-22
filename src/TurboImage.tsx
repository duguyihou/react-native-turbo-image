import React from 'react';
import {
  requireNativeComponent,
  NativeModules,
  type ProcessedColorValue,
  processColor,
  View,
  StyleSheet,
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

  const processedIndicator =
    indicator && Object.keys(indicator).length !== 0
      ? {
          style: indicator?.style,
          color: processColor(indicator?.color),
        }
      : undefined;

  return (
    <View
      style={[
        styles.imageContainer,
        { borderRadius: rounded ? 9999999 : borderRadius },
      ]}
    >
      <NativeImage
        {...restProps}
        cachePolicy={cachePolicy}
        resizeMode={resizeMode}
        indicator={processedIndicator}
        placeholder={placeholder}
        fadeDuration={fadeDuration}
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
    </View>
  );
};

const styles = StyleSheet.create({
  imageContainer: {
    overflow: 'hidden',
  },
});

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
