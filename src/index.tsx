import React, { forwardRef, memo } from 'react';
import type {
  TransformsStyle,
  StyleProp,
  ViewProps,
  AccessibilityProps,
  ShadowStyleIOS,
  FlexStyle,
  ImageResizeMode,
} from 'react-native';
import {
  Platform,
  UIManager,
  requireNativeComponent,
  NativeModules,
} from 'react-native';

const LINKING_ERROR =
  `The package 'react-native-turbo-image' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

export interface ImageStyle extends FlexStyle, TransformsStyle, ShadowStyleIOS {
  backfaceVisibility?: 'visible' | 'hidden';
  borderBottomLeftRadius?: number;
  borderBottomRightRadius?: number;
  backgroundColor?: string;
  borderColor?: string;
  borderWidth?: number;
  borderRadius?: number;
  borderTopLeftRadius?: number;
  borderTopRightRadius?: number;
  overlayColor?: string;
  opacity?: number;
}
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
  /**
   *
   * Style
   */
  style?: StyleProp<ImageStyle>;

  /**
   * A unique identifier for this element to be used in UI Automation testing scripts.
   */
  testID?: string;

  /**
   * Render children within the image.
   */
  children?: React.ReactNode;
}

const ComponentName = 'TurboImageView';

const TurboImageView =
  UIManager.getViewManagerConfig(ComponentName) != null
    ? requireNativeComponent<TurboImageProps>(ComponentName)
    : () => {
        throw new Error(LINKING_ERROR);
      };

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
