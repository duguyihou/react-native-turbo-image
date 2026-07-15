import { NativeModules } from 'react-native';
import type TurboImageType from '../TurboImage';

const mockManager = {
  prefetch: jest.fn().mockResolvedValue(true),
  clearMemoryCache: jest.fn().mockResolvedValue('Success'),
  clearDiskCache: jest.fn().mockResolvedValue('Success'),
};

// TurboImage.tsx destructures TurboImageViewManager off NativeModules at
// import time, so the mock must be installed before the module is required.
NativeModules.TurboImageViewManager = mockManager;
const TurboImage: typeof TurboImageType = require('../TurboImage').default;

beforeEach(() => {
  jest.clearAllMocks();
});

describe('TurboImage.prefetch', () => {
  it('forwards sources and default cachePolicy', async () => {
    const sources = [{ uri: 'https://example.com/a.png' }];
    await TurboImage.prefetch(sources);
    expect(mockManager.prefetch).toHaveBeenCalledWith(sources, 'urlCache');
  });

  it('forwards an explicit cachePolicy and resize field', async () => {
    const sources = [{ uri: 'https://example.com/a.png', resize: 100 }];
    await TurboImage.prefetch(sources, 'dataCache');
    expect(mockManager.prefetch).toHaveBeenCalledWith(sources, 'dataCache');
  });
});

describe('TurboImage.clearMemoryCache', () => {
  it('passes null when no sources are given (clears everything)', async () => {
    await TurboImage.clearMemoryCache();
    expect(mockManager.clearMemoryCache).toHaveBeenCalledWith(null);
  });

  it('forwards sources when given (scoped clear)', async () => {
    const sources = [{ uri: 'https://example.com/a.png' }];
    await TurboImage.clearMemoryCache(sources);
    expect(mockManager.clearMemoryCache).toHaveBeenCalledWith(sources);
  });
});

describe('TurboImage.clearDiskCache', () => {
  it('passes null when no sources are given (clears everything)', async () => {
    await TurboImage.clearDiskCache();
    expect(mockManager.clearDiskCache).toHaveBeenCalledWith(null);
  });

  it('forwards sources when given (scoped clear)', async () => {
    const sources = [{ uri: 'https://example.com/a.png', cacheKey: 'k' }];
    await TurboImage.clearDiskCache(sources);
    expect(mockManager.clearDiskCache).toHaveBeenCalledWith(sources);
  });
});
