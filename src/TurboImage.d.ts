import type { CachePolicy, ResizeMode, TurboImageApi } from './types';
import { type ColorValue } from 'react-native';

export interface TurboImageProps extends AccessibilityProps, ViewProps {
  src: string;
  resizeMode?: ResizeMode;
  showActivityIndicator?: boolean;
  blurhash?: string;
  fadeDuration?: number;
  borderRadius?: number;
  rounded?: boolean;
  blur?: number;
  monochrome?: number | ColorValue;
  cachePolicy?: CachePolicy;
  onSuccess?: () => void;
  onError?: (error: any) => void;
  ref?: LegacyRef<Component<TurboImageApi, {}, any>>;
  style?: StyleProp<ImageStyle>;
  testID?: string;
}

declare const TurboImage: React.FC<TurboImageProps> & TurboImageApi;

export default TurboImage;
