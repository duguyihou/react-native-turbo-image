import React, { forwardRef } from 'react';
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

const TurboImageView = forwardRef(
  (props: TurboImageProps, ref: React.LegacyRef<View>) => {
    const {
      source,
      style,
      cachePolicy,
      resizeMode,
      indicator,
      placeholder,
      fadeDuration,
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

    return (
      <View
        style={[
          styles.imageContainer,
          style,
          rounded && { borderRadius: 9999999 },
        ]}
        ref={ref}
      >
        <NativeImage
          {...restProps}
          style={StyleSheet.absoluteFill}
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
  }
);

const styles = StyleSheet.create({
  imageContainer: {
    overflow: 'hidden',
  },
});

const TurboImage = Object.assign({}, TurboImageView, {
  prefetch: async (sources: Source[]) => {
    return await TurboImageViewManager.prefetch(sources);
  },
  dispose: async (sources: Source[]) => {
    return await TurboImageViewManager.dispose(sources);
  },
  clearMemoryCache: async () => {
    return await TurboImageViewManager.clearMemoryCache();
  },
  clearDiskCache: async () => {
    return await TurboImageViewManager.clearDiskCache();
  },
});

export default TurboImage as React.FC<TurboImageProps> & TurboImageApi;
