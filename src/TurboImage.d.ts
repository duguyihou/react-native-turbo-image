import type { ResizeMode } from './types';
export interface TurboImageProps extends AccessibilityProps, ViewProps {
  url: string;
  resizeMode?: ResizeMode;
  showActivityIndicator?: boolean;
  base64Placeholder?: string;
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

declare const TurboImage: React.FC<TurboImageProps>;

export default TurboImage;
