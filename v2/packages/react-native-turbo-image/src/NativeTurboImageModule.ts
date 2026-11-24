// Codegen spec for the cache-management TurboModule (1.x's
// TurboImage.prefetch / dispose / clearMemoryCache / clearDiskCache).
//
// Sources are `UnsafeObject`s ({ uri, cacheKey? }) rather than a typed
// struct: Codegen would otherwise generate per-platform struct wrappers for
// an inline object type, and the native side re-validates every source
// through the C++ core anyway (the same `resolveRequest` views use, so keys
// agree between prefetch and display).
import { TurboModuleRegistry } from 'react-native';
import type { CodegenTypes, TurboModule } from 'react-native';

export interface Spec extends TurboModule {
  // Resolves true only if every source loaded (1.x resolved true even when
  // some failed). Invalid sources count as failures.
  prefetch(
    sources: ReadonlyArray<CodegenTypes.UnsafeObject>,
    cachePolicy: string
  ): Promise<boolean>;
  // Evicts the sources from the memory and disk caches. (Declared in 1.x
  // but never implemented natively on either platform.)
  dispose(sources: ReadonlyArray<CodegenTypes.UnsafeObject>): Promise<void>;
  clearMemoryCache(): Promise<void>;
  clearDiskCache(): Promise<void>;
  // Resolves `{ width, height }`: the image's own size in pixels, with its
  // orientation applied, read from the file's header after loading it into
  // the caches (no full decode for bitmaps). Rejects with a
  // `turboimage::LoadErrorCode` name as the code. New in 2.0.
  getSize(
    source: CodegenTypes.UnsafeObject,
    cachePolicy: string
  ): Promise<CodegenTypes.UnsafeObject>;
  // Sizes in bytes the caches are built with; 0 keeps the default. False,
  // and nothing changes, once the loader exists (its caches are built on
  // first use and cannot be resized). Synchronous, so it has taken effect
  // before the caller's next line, ahead of any image the app renders.
  // New in 2.0.
  configureCache(maxDiskSize: CodegenTypes.Double, maxMemoryCost: CodegenTypes.Double): boolean;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TurboImageModule');
