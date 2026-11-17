// Codegen spec for the TurboImage Fabric component.
//
// This file is the cross-platform contract between JS and native. Codegen
// reads it at build time to generate the C++ props/event structs (shared by
// iOS and Android), the ObjC++ `RCTComponentViewProtocol` glue, and the
// Kotlin `TurboImageViewManagerInterface`.
//
// Keep this spec free of loader concepts. Nothing here mentions Nuke or
// Coil: request semantics are owned by TurboImage (RFC rule 2) and the
// loaders are adapters behind the native layer (RFC rule 1).
import { codegenNativeComponent } from 'react-native';
import type { CodegenTypes, ColorValue, HostComponent, ViewProps } from 'react-native';

export type NativeHeader = Readonly<{ name: string; value: string }>;

export type NativeSource = Readonly<{
  uri: string;
  cacheKey?: string;
  // Sent with the request (e.g. auth). Not part of the cache key. An array
  // because Codegen props cannot express a free-form dictionary; the public
  // API accepts 1.x's record/pairs/Headers forms and converts them.
  headers?: ReadonlyArray<NativeHeader>;
}>;

// Shown until the image loads. If the load fails it is removed, unless
// `showPlaceholderOnFailure` is set. Decoded by the shared C++ core off the
// main thread. Provide at most one (validated in JS, development only).
export type NativePlaceholder = Readonly<{
  blurhash?: string;
  // Base64, as produced by `thumbhash`'s rgbaToThumbHash + base64 encoding.
  thumbhash?: string;
  // Show an image already in the *memory* cache (e.g. a thumbnail shown on
  // the previous screen) while this one loads. Pass the URI (or explicit
  // cacheKey) that image was loaded with; it is canonicalised by the core
  // exactly like a source, so keys always agree.
  memoryCacheKey?: string;
}>;

// Event payloads keep 1.x's names and fields so app handlers keep working
// (docs/migration-plan.md). Lifecycle per load:
//   onStart → onProgress* → (onSuccess | onFailure) → onCompletion
// A load superseded by a newer one ends with onCompletion {state:'cancelled'}
// and no success/failure (new in 2.0; 1.x declared but never sent it).
export type StartEvent = Readonly<{
  state: string; // 'running'
}>;

export type ProgressEvent = Readonly<{
  // Bytes. `total` is -1 when the server sends no Content-Length. Throttled
  // by the core to ~100 events per load (cpp/include/turboimage/Progress.h).
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
  // Stable, cross-platform classification; one of
  // 'invalidRequest' | 'notCached' | 'network' | 'decode' | 'unknown'.
  // Defined by `turboimage::LoadErrorCode` in cpp/include. New in 2.0.
  code: string;
  // Diagnostic text from the platform loader (1.x field name). Not stable
  // across platforms or versions; branch on `code` instead.
  error: string;
}>;

export type CompletionEvent = Readonly<{
  state: string; // 'completed' | 'cancelled'
}>;

export interface NativeProps extends ViewProps {
  source: NativeSource;
  placeholder?: NativePlaceholder;
  // These string unions mirror `turboimage::CachePolicy`; the native side
  // converts them to the pinned integer values in cpp/include.
  //
  // 'urlCache' is the only policy that obeys HTTP `Cache-Control`: its disk
  // tier is the platform's HTTP cache (keyed by URL, entries expire and are
  // revalidated, `no-store` is never stored), separate from the disk cache
  // the other policies share. So a 'cacheOnly' load does not see what a
  // 'urlCache' load stored on disk. The memory cache is shared by all.
  cachePolicy?: CodegenTypes.WithDefault<
    'default' | 'memoryOnly' | 'noCache' | 'cacheOnly' | 'urlCache',
    'default'
  >;
  // 'contain' is 1.x's default (React Native's <Image> defaults to 'cover');
  // kept for compatibility, see docs/migration-plan.md.
  resizeMode?: CodegenTypes.WithDefault<'cover' | 'contain' | 'stretch' | 'center', 'contain'>;
  // Identifies what this view is showing, for lists that reuse views
  // (FlashList). When a request prop changes, the image already on screen
  // stays until the new one has loaded, unless this key changed with it:
  // then the view is blanked (or shows the placeholder) first, so a reused
  // row never shows the previous row's image. New in 2.0; the same contract
  // as expo-image's prop of this name.
  recyclingKey?: string;
  // 1.x semantics: by default the placeholder is removed when the load
  // fails; true keeps it.
  showPlaceholderOnFailure?: CodegenTypes.WithDefault<boolean, false>;
  // Cross-fade from what is shown (the placeholder, the previous image or
  // blank) to the loaded image, in ms.
  // Skipped for memory-cache hits on both platforms. 0 disables it.
  fadeDuration?: CodegenTypes.WithDefault<CodegenTypes.Int32, 300>;
  // Image processors, applied by the shared C++ core in this order (see
  // cpp/include/turboimage/Processing.h). Each processed variant is its own
  // memory-cache entry; the disk cache keeps one original.
  // Target width in points/dp; aspect kept, never upscaled. 0 = off.
  resize?: CodegenTypes.WithDefault<CodegenTypes.Double, 0>;
  // Gaussian standard deviation in pixels of the (resized) image. 0 = off.
  blur?: CodegenTypes.WithDefault<CodegenTypes.Double, 0>;
  // Luminance mapped onto this colour ('white' = greyscale). The colour's
  // alpha is the effect's intensity.
  monochrome?: ColorValue;
  // Fills the image's opaque area with this colour, keeping transparency.
  tint?: ColorValue;
  // Decode the image no larger than it is shown: at the view's size, or at
  // `resize`'s width when that is set. A 12 MP photo in a thumbnail then
  // costs the thumbnail's memory, not 48 MB. Never upscales. `onSuccess`
  // reports the decoded size. Not applied with `resizeMode="center"` (drawn
  // 1:1) or `blur` without `resize` (its radius is in image pixels).
  //
  // Set false for a view that is zoomed or grows after the image loaded:
  // the size is taken when the load starts, and a later, larger layout
  // does not reload. New in 2.0; expo-image's prop of the same name.
  allowDownscaling?: CodegenTypes.WithDefault<boolean, true>;
  // Android only (ignored on iOS, as in 1.x): false decodes to a software
  // bitmap instead of a GPU-only hardware bitmap. Slower to draw; needed
  // only by code that reads the pixels or draws to a software canvas.
  allowHardware?: CodegenTypes.WithDefault<boolean, true>;
  // iOS 16+ only (ignored on Android, as in 1.x): select text, scan codes
  // and look up subjects in the loaded image with VisionKit.
  enableLiveTextInteraction?: CodegenTypes.WithDefault<boolean, false>;
  onStart?: CodegenTypes.DirectEventHandler<StartEvent>;
  onProgress?: CodegenTypes.DirectEventHandler<ProgressEvent>;
  onSuccess?: CodegenTypes.DirectEventHandler<SuccessEvent>;
  onFailure?: CodegenTypes.DirectEventHandler<FailureEvent>;
  onCompletion?: CodegenTypes.DirectEventHandler<CompletionEvent>;
}

export default codegenNativeComponent<NativeProps>('TurboImageView') as HostComponent<NativeProps>;
