import React from 'react';
import {
  requireNativeComponent,
  NativeModules,
  type ProcessedColorValue,
  processColor,
  View,
  StyleSheet,
  Image,
} from 'react-native';
import type {
  IndicatorStyle,
  Source,
  TurboImageApi,
  TurboImageProps,
} from './types';

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
    source,
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
    enableLiveTextInteraction,
    allowHardware,
    format,
    onStart,
    onSuccess,
    onFailure,
    onCompletion,
    ...restProps
  } = props;

  if (placeholder && Object.keys(placeholder).length > 1) {
    throw new Error('Choose one hash string, either thumbhash or blurhash');
  }

  const resolvedSource = (() => {
    if (typeof source === 'number') {
      return Image.resolveAssetSource(source);
    }
    return source;
  })();

  const processedIndicator =
    indicator && Object.keys(indicator).length !== 0
      ? {
          style: indicator?.style,
          color: processColor(indicator?.color),
        }
      : undefined;

  const containerStyle = [
    styles.imageContainer,
    { borderRadius: rounded ? 9999999 : borderRadius },
  ];

  return (
    <View style={containerStyle}>
      <NativeImage
        {...restProps}
        source={resolvedSource}
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
        enableLiveTextInteraction={enableLiveTextInteraction}
        allowHardware={allowHardware}
        format={format}
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

TurboImage.prefetch = async (sources: Source[]) => {
  return await TurboImageViewManager.prefetch(sources);
};

TurboImage.clearMemoryCache = async () => {
  return await TurboImageViewManager.clearMemoryCache();
};
TurboImage.clearDiskCache = async () => {
  return await TurboImageViewManager.clearDiskCache();
};

export default TurboImage as React.FC<TurboImageProps> & TurboImageApi;
