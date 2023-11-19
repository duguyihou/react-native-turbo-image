import type { ResizeMode } from './types';
export interface TurboImageProps extends AccessibilityProps, ViewProps {
  url: string;
  resizeMode?: ResizeMode;
  showActivityIndicator?: boolean;
  base64Placeholder?: string;
  fadeDuration?: number;
  rounded?: boolean;
  onSuccess?: () => void;
  onError?: (error: any) => void;
  ref?: React.Ref<any>;
  style?: StyleProp<ImageStyle>;
  testID?: string;
  children?: React.ReactNode;
}

declare const TurboImage: React.FC<TurboImageProps>;

export default TurboImage;
