import type {
  AccessibilityProps,
  ViewProps,
  StyleProp,
  ColorValue,
  NativeSyntheticEvent,
  ViewStyle,
} from 'react-native';

export type Source = {
  uri: string;
  headers?: HeadersInit_ | undefined;
  cacheKey?: String | undefined;
};

export type PrefetchSource = Source & {
  resize?: number;
};

export type PrefixFilter = {
  include_prefix?: string;
  exclude_prefix?: string;
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
  memoryCacheKey: string;
};

type TaskState = {
  state: State;
};

export type Start = TaskState;

export type Completion = TaskState;

export type Progress = {
  completed: number;
  total: number;
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
  style: StyleProp<ViewStyle>;
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
  isProgressiveImageRenderingEnabled?: boolean;
  allowHardware?: boolean;
  format?: Format;
  onStart?: (result: NativeSyntheticEvent<Start>) => void;
  onSuccess?: (result: NativeSyntheticEvent<Success>) => void;
  onProgress?: (result: NativeSyntheticEvent<Progress>) => void;
  onFailure?: (result: NativeSyntheticEvent<Failure>) => void;
  onCompletion?: (result: NativeSyntheticEvent<Completion>) => void;
}

export type TurboImageApi = {
  prefetch: (
    sources: PrefetchSource[],
    cachePolicy?: CachePolicy
  ) => Promise<boolean>;
  clearMemoryCache: (
    sources?: (PrefetchSource | PrefixFilter)[]
  ) => Promise<void>;
  clearDiskCache: (sources?: (Source | PrefixFilter)[]) => Promise<void>;
};
