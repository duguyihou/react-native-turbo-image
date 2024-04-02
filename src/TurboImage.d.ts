import type { CachePolicy, ResizeMode, TurboImageApi } from './types';
export interface TurboImageProps extends AccessibilityProps, ViewProps {
  url: string;
  resizeMode?: ResizeMode;
  showActivityIndicator?: boolean;
  base64Placeholder?: string;
  blurhash?: string;
  fadeDuration?: number;
  rounded?: boolean;
  blur?: boolean;
  cachePolicy?: CachePolicy;
  onSuccess?: () => void;
  onError?: (error: any) => void;
  ref?: LegacyRef<Component<TurboImageApi, {}, any>>;
  style?: StyleProp<ImageStyle>;
  testID?: string;
  children?: React.ReactNode;
}

declare const TurboImage: React.FC<TurboImageProps> & TurboImageApi;

export default TurboImage;
