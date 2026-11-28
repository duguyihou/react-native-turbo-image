// Codegen spec for the cache TurboModule.
// Sources are `UnsafeObject`s to avoid per-platform struct wrappers; native
// validates them through the core, as views do, so cache keys agree.
import { TurboModuleRegistry } from 'react-native';
import type { CodegenTypes, TurboModule } from 'react-native';

export interface Spec extends TurboModule {
  // True only if every source loaded. Downloads to disk without decoding.
  prefetch(
    sources: ReadonlyArray<CodegenTypes.UnsafeObject>,
    cachePolicy: string
  ): Promise<boolean>;
  // Evicts the sources from memory and disk.
  dispose(sources: ReadonlyArray<CodegenTypes.UnsafeObject>): Promise<void>;
  clearMemoryCache(): Promise<void>;
  clearDiskCache(): Promise<void>;
  // Resolves `{ width, height }` in pixels from the file header. Rejects with
  // a `turboimage::LoadErrorCode` name.
  getSize(
    source: CodegenTypes.UnsafeObject,
    cachePolicy: string
  ): Promise<CodegenTypes.UnsafeObject>;
  // Bytes; 0 keeps the default. False if the caches already exist.
  // Synchronous so it applies before the first image.
  configureCache(maxDiskSize: CodegenTypes.Double, maxMemoryCost: CodegenTypes.Double): boolean;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TurboImageModule');
