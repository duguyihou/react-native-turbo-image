// Runs once, from a bare `import './src/startup'` at the top of index.js:
// before any <TurboImage> mounts or any other TurboImage call, which is the
// only time `configureCache` applies. A real app does the same in its entry
// file.
import { TurboImage } from 'react-native-turbo-image';

// 200 MB of disk instead of the default 150 MB, so the Performance screen's
// 1000-image datasets fit. The memory cache keeps its device-scaled default.
// The smoke test's `configureCache` scenario checks this call returned true.
export const cacheConfigured: boolean = TurboImage.configureCache({
  maxDiskSize: 200 * 1024 * 1024,
});
