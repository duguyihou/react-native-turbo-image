import React, { forwardRef, memo } from 'react';
import type { TransformsStyle } from 'react-native';
import type { StyleProp } from 'react-native';
import type { ViewProps } from 'react-native';
import type { ColorValue } from 'react-native';
import type { AccessibilityProps } from 'react-native';
import type { ShadowStyleIOS } from 'react-native';
import type { FlexStyle } from 'react-native';
import {
  View,
  StyleSheet,
  requireNativeComponent,
  UIManager,
  Platform,
} from 'react-native';

const LINKING_ERROR =
  `The package 'react-native-turbo-image' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

export type ResizeMode = 'contain' | 'cover' | 'stretch' | 'center';

const resizeMode = {
  contain: 'contain',
  cover: 'cover',
  stretch: 'stretch',
  center: 'center',
} as const;
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
  source: string;
  /**
   *
   * Style
   */
  style?: StyleProp<ImageStyle>;

  /**
   * TintColor
   * If supplied, changes the color of all the non-transparent pixels to the given color.
   */
  tintColor?: ColorValue;

  /**
   * A unique identifier for this element to be used in UI Automation testing scripts.
   */
  testID?: string;

  /**
   * Render children within the image.
   */
  children?: React.ReactNode;
  width: number;
  height: number;
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
    source,
    tintColor,
    style,
    children,
    forwardedRef,
    width,
    height,
    ...restProps
  } = props;
  const containerStyle = {
    width,
    height,
  };
  return (
    <View
      style={[styles.imageContainer, style, containerStyle]}
      ref={forwardedRef}
    >
      <TurboImageView
        {...restProps}
        tintColor={tintColor}
        style={StyleSheet.absoluteFill}
        source={source}
        width={width}
        height={height}
      />
      {children}
    </View>
  );
};

const styles = StyleSheet.create({
  imageContainer: {
    overflow: 'hidden',
  },
});

const TurboImageMemo = memo(TurboImageBase);

const TurboImageComponent: React.ComponentType<TurboImageProps> = forwardRef(
  (props: TurboImageProps, ref: React.Ref<any>) => (
    <TurboImageMemo forwardedRef={ref} {...props} />
  )
);

TurboImageComponent.displayName = 'TurboImage';

export interface TurboImageStaticProperties {
  resizeMode: typeof resizeMode;
}

const TurboImage: React.ComponentType<TurboImageProps> &
  TurboImageStaticProperties = TurboImageComponent as any;

// TurboImage.resizeMode = resizeMode;

export default TurboImage;
