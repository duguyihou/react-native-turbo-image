import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Image, StyleSheet, View } from 'react-native';
import type { ColorValue } from 'react-native';

import NativeTurboImageModule from './NativeTurboImageModule';
import TurboImageView from './TurboImageViewNativeComponent';
import type { NativeHeader, NativeProps, NativeSource } from './TurboImageViewNativeComponent';

export type {
  CompletionEvent,
  FailureEvent,
  NativePlaceholder as Placeholder,
  ProgressEvent,
  StartEvent,
  SuccessEvent,
} from './TurboImageViewNativeComponent';

// 1.x's `source.headers` forms: a record, [name, value] pairs, or a fetch
// `Headers` object (anything with forEach(value, name)).
export type HeadersInput =
  | Readonly<Record<string, string>>
  | ReadonlyArray<readonly [string, string]>
  | { forEach(callback: (value: string, name: string) => void): void };

export type RemoteSource = Omit<NativeSource, 'headers'> & { headers?: HeadersInput };

// A URI source, or a bundled asset from `require('./logo.png')` (new in 2.0).
// URIs may be http(s), `file://`, and on Android `content://` or
// `android.resource://`.
export type Source = RemoteSource | number;

function toNativeHeaders(headers: HeadersInput | undefined): NativeHeader[] | undefined {
  if (headers == null) {
    return undefined;
  }
  const out: NativeHeader[] = [];
  if (Array.isArray(headers)) {
    for (const [name, value] of headers as ReadonlyArray<readonly [string, string]>) {
      out.push({ name, value: String(value) });
    }
  } else if (typeof (headers as { forEach?: unknown }).forEach === 'function') {
    (headers as { forEach(cb: (v: string, n: string) => void): void }).forEach((value, name) =>
      out.push({ name, value: String(value) })
    );
  } else {
    for (const [name, value] of Object.entries(headers as Record<string, string>)) {
      out.push({ name, value: String(value) });
    }
  }
  return out;
}

function toNativeSource(source: Source): NativeSource {
  if (typeof source === 'number') {
    // RN's resolver picks the @2x/@3x file for this screen and returns a
    // dev-server URL in development, a `file://` bundle URL on iOS release,
    // and a bare resource name on Android release (resolved natively).
    // An unknown asset id resolves to null: an empty URI the core rejects.
    return { uri: Image.resolveAssetSource(source)?.uri ?? '' };
  }
  const { headers, ...rest } = source;
  const native = toNativeHeaders(headers);
  return native === undefined ? rest : { ...rest, headers: native };
}

// 2.0's cache policies, owned by the C++ core (cpp/include/turboimage).
export type CachePolicy = NonNullable<NativeProps['cachePolicy']>;

// 1.x policy names, still accepted so apps can upgrade without edits.
// TODO: remove in 3.0.
export type LegacyCachePolicy = 'urlCache' | 'dataCache';

export type TurboImageProps = Omit<NativeProps, 'cachePolicy' | 'monochrome' | 'tint' | 'source'> & {
  source: Source;
  cachePolicy?: CachePolicy | LegacyCachePolicy;
  // 1.x also accepted RN's numeric colour form (0xRRGGBBAA); RN's colour
  // processing handles both, Codegen's ColorValue just doesn't spell it.
  monochrome?: ColorValue | number;
  tint?: ColorValue | number;
  // 1.x prop: clip the image to a circle/pill.
  rounded?: boolean;
  // 1.x prop: an activity spinner while the image loads. Not shown when a
  // `placeholder` is given (1.x Android's rule; on 1.x iOS whichever prop
  // was set last won).
  indicator?: Indicator;
  /**
   * @deprecated Ignored. 1.x needed it to pick a GIF/APNG/SVG decoder; 2.0
   * detects the format from the image bytes on both platforms.
   */
  format?: 'svg' | 'gif' | 'apng' | string;
};

export type Indicator = {
  style?: 'medium' | 'large';
  color?: ColorValue | number;
};

// A load that finishes sooner than this never shows the spinner. Memory and
// disk hits complete within a frame or two; a spinner that appears and
// vanishes that fast reads as flicker (1.x avoided it only because Nuke and
// Coil resolved memory hits synchronously). As a side effect such loads
// cause no extra React render at all.
const INDICATOR_DELAY_MS = 150;

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

function TurboImageComponent({
  cachePolicy,
  rounded,
  style,
  source,
  // Accepted for 1.x compatibility and dropped; see the type's note.
  format: _format,
  indicator,
  onStart,
  onCompletion,
  ...props
}: TurboImageProps) {
  // The spinner is plain React: an <ActivityIndicator> over the native view,
  // driven by the load events, so it is identical on both platforms and
  // needs no native code. `onCompletion` ends every load that `onStart`
  // began (success, failure or cancelled), so those two events suffice.
  //
  // 1.x quirk kept: an empty object (`indicator={{}}`) means no indicator.
  const showsIndicator =
    indicator != null && Object.keys(indicator).length > 0 && !props.placeholder;
  const [spinning, setSpinning] = useState(false);
  const spinTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(spinTimer.current), []);

  const handleStart: NativeProps['onStart'] = (event) => {
    clearTimeout(spinTimer.current);
    spinTimer.current = setTimeout(() => setSpinning(true), INDICATOR_DELAY_MS);
    return onStart?.(event);
  };
  const handleCompletion: NativeProps['onCompletion'] = (event) => {
    clearTimeout(spinTimer.current);
    setSpinning(false); // no re-render if it never started spinning
    return onCompletion?.(event);
  };

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

  const needsContainer = rounded || showsIndicator;
  const image = (
    <TurboImageView
      {...(props as Omit<NativeProps, 'cachePolicy' | 'source'>)}
      // A new object each render is fine: both native views compare the
      // request fields by value before reloading.
      source={toNativeSource(source)}
      style={needsContainer ? StyleSheet.absoluteFill : style}
      cachePolicy={resolveCachePolicy(cachePolicy)}
      // Without an indicator the app's handlers go straight through.
      onStart={showsIndicator ? handleStart : onStart}
      onCompletion={showsIndicator ? handleCompletion : onCompletion}
    />
  );
  if (!needsContainer) {
    return image;
  }
  // The same approach as 1.x: clip in a container. The native image view
  // itself does not clip to borderRadius on Android (ImageView content is not
  // clipped by RN's border drawing), so a clipping container keeps both
  // platforms identical. The container must not come and go with the
  // spinner: that would remount the native view and restart the load.
  return (
    <View style={[style, rounded && styles.rounded]}>
      {image}
      {showsIndicator && spinning && (
        <ActivityIndicator
          style={StyleSheet.absoluteFill}
          pointerEvents="none"
          // RN's 'small' is UIKit's `.medium` style, which is 1.x's 'medium'.
          size={indicator.style === 'large' ? 'large' : 'small'}
          color={indicator.color as ColorValue | undefined}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  rounded: { overflow: 'hidden', borderRadius: 9999 },
});

type CacheSource = Source;

// 1.x exposed these as statics on the component; kept for compatibility.
export const TurboImage = Object.assign(TurboImageComponent, {
  prefetch: (
    sources: CacheSource[],
    cachePolicy: TurboImageProps['cachePolicy'] = 'default'
  ): Promise<boolean> =>
    NativeTurboImageModule.prefetch(
      sources.map(toNativeSource),
      resolveCachePolicy(cachePolicy) ?? 'default'
    ),
  dispose: (sources: CacheSource[]): Promise<void> =>
    NativeTurboImageModule.dispose(sources.map(toNativeSource)),
  clearMemoryCache: (): Promise<void> => NativeTurboImageModule.clearMemoryCache(),
  clearDiskCache: (): Promise<void> => NativeTurboImageModule.clearDiskCache(),
});

export default TurboImage;
