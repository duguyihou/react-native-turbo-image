import type {
  CachePolicy,
  Failure,
  ResizeMode,
  Success,
  TurboImageApi,
} from './types';
import { type ColorValue, type NativeSyntheticEvent } from 'react-native';

export interface TurboImageProps extends AccessibilityProps, ViewProps {
  src: string;
  style: StyleProp<ImageStyle>;
  resizeMode?: ResizeMode;
  showActivityIndicator?: boolean;
  blurhash?: string;
  fadeDuration?: number;
  borderRadius?: number;
  rounded?: boolean;
  blur?: number;
  monochrome?: number | ColorValue;
  cachePolicy?: CachePolicy;
  onSuccess?: (result: NativeSyntheticEvent<Success>) => void;
  onFailure?: (result: NativeSyntheticEvent<Failure>) => void;
  ref?: LegacyRef<Component<TurboImageApi, {}, any>>;
  testID?: string;
}

declare const TurboImage: React.FC<TurboImageProps> & TurboImageApi;

export default TurboImage;
