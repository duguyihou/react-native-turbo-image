import type {
  AccessibilityProps,
  ViewProps,
  StyleProp,
  ImageStyle,
  ColorValue,
  NativeSyntheticEvent,
} from 'react-native';

export type ResizeMode = 'contain' | 'cover' | 'stretch' | 'center';
export const resizeMode = {
  contain: 'contain',
  cover: 'cover',
  stretch: 'stretch',
  center: 'center',
} as const;

export type CachePolicy = 'memory' | 'urlCache' | 'dataCache';

export const cachePolicy = {
  memory: 'memory',
  urlCache: 'urlCache',
  dataCache: 'dataCache',
} as const;

export type TaskState = 'running' | 'cancelled' | 'completed';

export type Start = {
  state: string;
};

export type Success = {
  width: number;
  height: number;
  source: string;
};

export type Failure = {
  error: string;
};

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
  resize?: number[];
  cachePolicy?: CachePolicy;
  onStart?: (result: NativeSyntheticEvent<Start>) => void;
  onSuccess?: (result: NativeSyntheticEvent<Success>) => void;
  onFailure?: (result: NativeSyntheticEvent<Failure>) => void;
}

export type TurboImageApi = {
  prefetch: (sources: string[]) => Promise<void>;
  clearMemoryCache: () => Promise<void>;
  clearDiskCache: () => Promise<void>;
};
