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

export type TurboImageApi = {
  prefetch: (sources: string[]) => Promise<void>;
  clearMemoryCache: () => Promise<void>;
  clearDiskCache: () => Promise<void>;
};

type State = 'running' | 'cancelled' | 'completed';
export type TaskState = {
  state: State;
};
export type SuccessResult = {
  nativeEvent: {
    width: number;
    height: number;
    source: string;
  };
};

export type FailureResult = {
  nativeEvent: {
    error: string;
  };
};
