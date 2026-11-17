import { StyleSheet, View } from 'react-native';
import type { ColorValue } from 'react-native';

import NativeTurboImageModule from './NativeTurboImageModule';
import TurboImageView from './TurboImageViewNativeComponent';
import type { NativeProps } from './TurboImageViewNativeComponent';

export type {
  CompletionEvent,
  FailureEvent,
  NativePlaceholder as Placeholder,
  NativeSource as Source,
  ProgressEvent,
  StartEvent,
  SuccessEvent,
} from './TurboImageViewNativeComponent';

// 2.0's cache policies, owned by the C++ core (cpp/include/turboimage).
export type CachePolicy = NonNullable<NativeProps['cachePolicy']>;

// 1.x policy names, still accepted so apps can upgrade without edits.
// TODO: remove in 3.0.
export type LegacyCachePolicy = 'urlCache' | 'dataCache';

export type TurboImageProps = Omit<NativeProps, 'cachePolicy' | 'monochrome' | 'tint'> & {
  cachePolicy?: CachePolicy | LegacyCachePolicy;
  // 1.x also accepted processColor() output (a number); RN's colour
  // processing handles both, Codegen's ColorValue just doesn't spell it.
  monochrome?: ColorValue | number;
  tint?: ColorValue | number;
  // 1.x prop: clip the image to a circle/pill.
  rounded?: boolean;
};

// Maps 1.x names onto 2.0 policies.
//   * 'dataCache' was 1.x iOS's aggressive data cache; 2.0's 'default' is
//     exactly that on both platforms (RFC §4.2).
//   * 'urlCache' respected HTTP Cache-Control on iOS. 2.0 deliberately
//     ignores HTTP freshness on both platforms, so it also maps to 'default',
//     with a development-time warning because behaviour can differ.
const warned = new Set<string>();
function resolveCachePolicy(
  policy: TurboImageProps['cachePolicy']
): CachePolicy | undefined {
  if (policy !== 'urlCache' && policy !== 'dataCache') {
    return policy;
  }
  if (__DEV__ && !warned.has(policy)) {
    warned.add(policy);
    console.warn(
      policy === 'urlCache'
        ? "TurboImage: cachePolicy 'urlCache' is deprecated and now behaves like 'default'; " +
            'HTTP Cache-Control headers are no longer honoured. See the 2.0 migration guide.'
        : "TurboImage: cachePolicy 'dataCache' is deprecated; use 'default' (same behaviour)."
    );
  }
  return 'default';
}

function TurboImageComponent({ cachePolicy, rounded, style, ...props }: TurboImageProps) {
  // Same rule as 1.x: one placeholder kind at a time. Native would silently
  // pick one; failing loudly in development is kinder.
  if (__DEV__ && props.placeholder) {
    const kinds = Object.values(props.placeholder).filter(Boolean).length;
    if (kinds > 1) {
      throw new Error(
        'TurboImage: choose only one placeholder (blurhash, thumbhash or memoryCacheKey)'
      );
    }
  }

  const image = (
    <TurboImageView
      {...(props as Omit<NativeProps, 'cachePolicy'>)}
      style={rounded ? StyleSheet.absoluteFill : style}
      cachePolicy={resolveCachePolicy(cachePolicy)}
    />
  );
  if (!rounded) {
    return image;
  }
  // The same approach as 1.x: clip in a container. The native image view
  // itself does not clip to borderRadius on Android (ImageView content is not
  // clipped by RN's border drawing), so a clipping container keeps both
  // platforms identical.
  return <View style={[style, styles.rounded]}>{image}</View>;
}

const styles = StyleSheet.create({
  rounded: { overflow: 'hidden', borderRadius: 9999 },
});

type CacheSource = { uri: string; cacheKey?: string };

// 1.x exposed these as statics on the component; kept for compatibility.
export const TurboImage = Object.assign(TurboImageComponent, {
  prefetch: (
    sources: CacheSource[],
    cachePolicy: TurboImageProps['cachePolicy'] = 'default'
  ): Promise<boolean> =>
    NativeTurboImageModule.prefetch(sources, resolveCachePolicy(cachePolicy) ?? 'default'),
  dispose: (sources: CacheSource[]): Promise<void> =>
    NativeTurboImageModule.dispose(sources),
  clearMemoryCache: (): Promise<void> => NativeTurboImageModule.clearMemoryCache(),
  clearDiskCache: (): Promise<void> => NativeTurboImageModule.clearDiskCache(),
});

export default TurboImage;
