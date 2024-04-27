import type {
  CachePolicy,
  FailureResult,
  ResizeMode,
  SuccessResult,
  TaskState,
  TurboImageApi,
} from './types';
import { type ColorValue } from 'react-native';

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
  onStart?: (state: TaskState) => void;
  onSuccess?: (result: SuccessResult) => void;
  onFailure?: (result: FailureResult) => void;
  ref?: LegacyRef<Component<TurboImageApi, {}, any>>;
  testID?: string;
}

declare const TurboImage: React.FC<TurboImageProps> & TurboImageApi;

export default TurboImage;
