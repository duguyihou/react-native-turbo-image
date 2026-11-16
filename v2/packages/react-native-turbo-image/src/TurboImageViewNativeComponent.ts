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
import type { CodegenTypes, HostComponent, ViewProps } from 'react-native';

export type NativeSource = Readonly<{
  uri: string;
  cacheKey?: string;
}>;

// Shown until the image loads, and kept if it fails. Decoded by the shared
// C++ core off the main thread. Provide at most one (validated in JS).
// TODO: 1.x's `memoryCacheKey` placeholder needs an adapter cache-lookup
// API on the seam; it lands with the prefetch/cache TurboModule.
export type NativePlaceholder = Readonly<{
  blurhash?: string;
  // Base64, as produced by `thumbhash`'s rgbaToThumbHash + base64 encoding.
  thumbhash?: string;
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
  cachePolicy?: CodegenTypes.WithDefault<
    'default' | 'memoryOnly' | 'noCache' | 'cacheOnly',
    'default'
  >;
  resizeMode?: CodegenTypes.WithDefault<
    'cover' | 'contain' | 'stretch' | 'center',
    'cover'
  >;
  onStart?: CodegenTypes.DirectEventHandler<StartEvent>;
  onProgress?: CodegenTypes.DirectEventHandler<ProgressEvent>;
  onSuccess?: CodegenTypes.DirectEventHandler<SuccessEvent>;
  onFailure?: CodegenTypes.DirectEventHandler<FailureEvent>;
  onCompletion?: CodegenTypes.DirectEventHandler<CompletionEvent>;
}

export default codegenNativeComponent<NativeProps>(
  'TurboImageView'
) as HostComponent<NativeProps>;
