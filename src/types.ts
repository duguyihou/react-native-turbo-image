export type ResizeMode = 'contain' | 'cover' | 'stretch' | 'center';
export const resizeMode = {
  contain: 'contain',
  cover: 'cover',
  stretch: 'stretch',
  center: 'center',
} as const;

export type CachePolicy = 'shared' | 'memory';

export const cachePolicy = {
  shared: 'shared',
  memory: 'memory',
} as const;

export type TurboImageApi = {
  prefetch: (urls: string[]) => Promise<void>;
  clearAllCache: () => Promise<void>;
  clearMemoryCache: () => Promise<void>;
  clearDiskCache: () => Promise<void>;
};
