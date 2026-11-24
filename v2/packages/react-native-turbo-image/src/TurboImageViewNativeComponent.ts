// Codegen spec for the TurboImage Fabric component: the JS/native contract.
// Keep it free of loader concepts (no Nuke or Coil; RFC rules 1 and 2).
import { codegenNativeComponent } from 'react-native';
import type { CodegenTypes, ColorValue, HostComponent, ViewProps } from 'react-native';

export type NativeHeader = Readonly<{ name: string; value: string }>;

export type NativeSource = Readonly<{
  uri: string;
  cacheKey?: string;
  // Not part of the cache key. An array: Codegen has no free-form dictionary.
  headers?: ReadonlyArray<NativeHeader>;
}>;

// Shown until the image loads; removed on failure unless
// `showPlaceholderOnFailure`. Set at most one field.
export type NativePlaceholder = Readonly<{
  blurhash?: string;
  // Base64 of `thumbhash`'s rgbaToThumbHash output.
  thumbhash?: string;
  /**
   * An image already in the *memory* cache: the URI or cacheKey it was
   * loaded with.
   * @deprecated Use `uri`, which also finds it in the caches. Removed in 3.0.
   */
  memoryCacheKey?: string;
  // Any image, e.g. a thumbnail. Loaded with the source's headers,
  // unprocessed, without events; never shown over the loaded image.
  uri?: string;
}>;

// Event payloads keep 1.x's names. Per load:
//   onStart → onProgress* → (onSuccess | onFailure) → onCompletion
// A superseded load ends with onCompletion {state:'cancelled'} only.
export type StartEvent = Readonly<{
  state: string; // 'running'
}>;

export type ProgressEvent = Readonly<{
  // Bytes; `total` is -1 without Content-Length. ~100 events per load at most.
  completed: CodegenTypes.Double;
  total: CodegenTypes.Double;
}>;

export type SuccessEvent = Readonly<{
  width: CodegenTypes.Double;
  height: CodegenTypes.Double;
  // The URL that was loaded.
  source: string;
}>;

export type FailureEvent = Readonly<{
  // Stable across platforms (`turboimage::LoadErrorCode`):
  // 'invalidRequest' | 'notCached' | 'network' | 'decode' | 'unknown'.
  code: string;
  // Loader diagnostic text; not stable, branch on `code` instead.
  error: string;
}>;

export type CompletionEvent = Readonly<{
  state: string; // 'completed' | 'cancelled'
}>;

export interface NativeProps extends ViewProps {
  source: NativeSource;
  placeholder?: NativePlaceholder;
  // Mirrors `turboimage::CachePolicy`. Only 'urlCache' obeys HTTP
  // `Cache-Control`; its disk store is the platform HTTP cache, separate from
  // the others' (so 'cacheOnly' can't see it). The memory cache is shared.
  // On iOS, responses over 7.5 MB are never stored by 'urlCache'.
  cachePolicy?: CodegenTypes.WithDefault<
    'default' | 'memoryOnly' | 'noCache' | 'cacheOnly' | 'urlCache',
    'default'
  >;
  // Defaults to 'contain' as in 1.x (RN <Image> uses 'cover').
  // 'scale-down': 'center' if the image fits, else 'contain'.
  resizeMode?: CodegenTypes.WithDefault<
    'cover' | 'contain' | 'stretch' | 'center' | 'scale-down',
    'contain'
  >;
  // Fraction of the free space: 0 = left/top, 0.5 = centred, 1 = right/bottom.
  contentPositionX?: CodegenTypes.WithDefault<CodegenTypes.Double, 0.5>;
  contentPositionY?: CodegenTypes.WithDefault<CodegenTypes.Double, 0.5>;
  // For recycled list rows. On a source change the old image stays until
  // the new one loads, unless this key also changed: then the view clears
  // first, so a reused row never shows the previous row's image.
  recyclingKey?: string;
  // Keep the placeholder when the load fails.
  showPlaceholderOnFailure?: CodegenTypes.WithDefault<boolean, false>;
  // Cross-fade to the loaded image, in ms. Skipped on memory hits; 0 = off.
  fadeDuration?: CodegenTypes.WithDefault<CodegenTypes.Int32, 300>;
  // Processors, applied in this order. Each variant is cached in memory
  // separately; disk keeps one original.
  // Target width in points/dp; aspect kept, never upscaled. 0 = off.
  resize?: CodegenTypes.WithDefault<CodegenTypes.Double, 0>;
  // Gaussian sigma in pixels of the (resized) image. 0 = off.
  blur?: CodegenTypes.WithDefault<CodegenTypes.Double, 0>;
  // Map luminance onto this colour ('white' = greyscale); alpha = intensity.
  monochrome?: ColorValue;
  // Fill the opaque area with this colour.
  tint?: ColorValue;
  // Decode no larger than shown (view size, or `resize`). `onSuccess` reports
  // the decoded size. Not applied with `resizeMode="center"` or with `blur`
  // but no `resize`. Growing past 1.5x reloads silently at the new size; set
  // false for images zoomed by `transform`. No effect on SVGs.
  allowDownscaling?: CodegenTypes.WithDefault<boolean, true>;
  // Android only. False uses a software bitmap, needed only to read pixels
  // or draw to a software canvas.
  allowHardware?: CodegenTypes.WithDefault<boolean, true>;
  // iOS only (not tvOS): VisionKit Live Text on the loaded image.
  enableLiveTextInteraction?: CodegenTypes.WithDefault<boolean, false>;
  // Internal: set by <TurboImage> when `onProgress` has a handler, so loads
  // skip progress work otherwise. Read at load start.
  progressEnabled?: CodegenTypes.WithDefault<boolean, false>;
  // Internal: bits for which of onStart (1), onSuccess (2), onFailure (4),
  // onCompletion (8) have handlers; others are not sent. Read at emit time.
  // All on by default, for use without <TurboImage>.
  loadEventMask?: CodegenTypes.WithDefault<CodegenTypes.Int32, 15>;
  onStart?: CodegenTypes.DirectEventHandler<StartEvent>;
  onProgress?: CodegenTypes.DirectEventHandler<ProgressEvent>;
  onSuccess?: CodegenTypes.DirectEventHandler<SuccessEvent>;
  onFailure?: CodegenTypes.DirectEventHandler<FailureEvent>;
  onCompletion?: CodegenTypes.DirectEventHandler<CompletionEvent>;
}

export default codegenNativeComponent<NativeProps>('TurboImageView') as HostComponent<NativeProps>;
