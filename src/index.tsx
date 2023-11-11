import React, { forwardRef, memo } from 'react';
import type {
  StyleProp,
  ViewProps,
  AccessibilityProps,
  ImageResizeMode,
  ImageStyle,
} from 'react-native';
import { requireNativeComponent, NativeModules } from 'react-native';

export interface TurboImageProps extends AccessibilityProps, ViewProps {
  url: string;
  resizeMode?: ImageResizeMode;
  onError?: (result: { nativeEvent: { error: string } }) => void;
  onSuccess?: (result: {
    nativeEvent: {
      width: number;
      height: number;
      source: string;
    };
  }) => void;
  ref?: React.Ref<any>;
  style?: StyleProp<ImageStyle>;
  testID?: string;
  children?: React.ReactNode;
}

const ComponentName = 'TurboImageView';

const TurboImageView = requireNativeComponent<TurboImageProps>(ComponentName);

const TurboImageBase = (
  props: TurboImageProps & { forwardedRef: React.Ref<any> }
) => {
  const {
    url,
    onError,
    onSuccess,
    style,
    forwardedRef,
    resizeMode,
    ...restProps
  } = props;

  return (
    <TurboImageView
      {...restProps}
      onError={onError}
      onSuccess={onSuccess}
      style={style}
      url={url}
      resizeMode={resizeMode}
      ref={forwardedRef}
    />
  );
};

const TurboImageMemo = memo(TurboImageBase);

const TurboImageComponent: React.ComponentType<TurboImageProps> = forwardRef(
  (props: TurboImageProps, ref: React.Ref<any>) => (
    <TurboImageMemo forwardedRef={ref} {...props} />
  )
);

TurboImageComponent.displayName = 'TurboImage';

const { TurboImageViewManager } = NativeModules;

const TurboImage: React.ComponentType<TurboImageProps> = Object.assign(
  TurboImageComponent,
  TurboImageViewManager
);

export default TurboImage;
