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

export type LoadEvent = Readonly<{
  width: CodegenTypes.Double;
  height: CodegenTypes.Double;
}>;

export type ErrorEvent = Readonly<{
  message: string;
}>;

export interface NativeProps extends ViewProps {
  source: NativeSource;
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
  onLoad?: CodegenTypes.DirectEventHandler<LoadEvent>;
  onError?: CodegenTypes.DirectEventHandler<ErrorEvent>;
}

export default codegenNativeComponent<NativeProps>(
  'TurboImageView'
) as HostComponent<NativeProps>;
