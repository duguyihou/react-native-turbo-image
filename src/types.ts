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

export type Success = {
  width: number;
  height: number;
  source: string;
};

export type Failure = {
  error: string;
};
