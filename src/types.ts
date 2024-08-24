import type {
  AccessibilityProps,
  ViewProps,
  StyleProp,
  ImageStyle,
  ColorValue,
  NativeSyntheticEvent,
} from 'react-native';

export type Source = {
  uri: string;
  headers?: HeadersInit_ | undefined;
};

export type IndicatorStyle = 'large' | 'medium';
export type Indicator = Partial<{
  style: IndicatorStyle;
  color: number | ColorValue;
}>;
export type ResizeMode = 'contain' | 'cover' | 'stretch' | 'center';

export type CachePolicy = 'urlCache' | 'dataCache';

export type Format = 'svg' | 'gif' | 'apng';

type State = 'running' | 'cancelled' | 'completed';

export type Placeholder = {
  blurhash: string;
  thumbhash: string;
};

export type TaskState = {
  state: State;
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
  source: Source;
  style: StyleProp<ImageStyle>;
  resizeMode?: ResizeMode;
  indicator?: Indicator;
  placeholder?: Partial<Placeholder>;
  showPlaceholderOnFailure?: boolean;
  fadeDuration?: number;
  rounded?: boolean;
  blur?: number;
  monochrome?: number | ColorValue;
  resize?: number;
  tint?: number | ColorValue;
  cachePolicy?: CachePolicy;
  enableLiveTextInteraction?: boolean;
  allowHardware?: boolean;
  format?: Format;
  onStart?: (result: NativeSyntheticEvent<TaskState>) => void;
  onSuccess?: (result: NativeSyntheticEvent<Success>) => void;
  onFailure?: (result: NativeSyntheticEvent<Failure>) => void;
  onCompletion?: (result: NativeSyntheticEvent<TaskState>) => void;
}

export type TurboImageApi = {
  prefetch: (sources: Source[]) => Promise<void>;
  dispose: (sources: Source[]) => Promise<void>;
  clearMemoryCache: () => Promise<void>;
  clearDiskCache: () => Promise<void>;
};
