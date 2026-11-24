import { useEffect, useRef, useState } from 'react';
import type { ComponentRef, Ref } from 'react';
import { ActivityIndicator, Image, StyleSheet, View } from 'react-native';
import type { ColorValue } from 'react-native';

import NativeTurboImageModule from './NativeTurboImageModule';
import TurboImageView from './TurboImageViewNativeComponent';
import type {
  CompletionEvent,
  FailureEvent,
  NativeHeader,
  NativeProps,
  NativeSource,
  ProgressEvent,
  StartEvent,
  SuccessEvent,
} from './TurboImageViewNativeComponent';

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
// 1.x's exported type names, kept so `import type { Success } from
// 'react-native-turbo-image'` still compiles. TODO: remove in 3.0.
export type Start = StartEvent;
export type Progress = ProgressEvent;
export type Success = SuccessEvent;
export type Failure = FailureEvent;
export type Completion = CompletionEvent;
export type ResizeMode = NonNullable<NativeProps['resizeMode']>;
export type IndicatorStyle = NonNullable<Indicator['style']>;
export type Format = 'svg' | 'gif' | 'apng';

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

// 1.x policy name, still accepted so apps can upgrade without edits. 1.x's
// other name, 'urlCache', is a real 2.0 policy again (see the native spec).
// TODO: remove in 3.0.
export type LegacyCachePolicy = 'dataCache';

export type TurboImageProps = Omit<
  NativeProps,
  'cachePolicy' | 'monochrome' | 'tint' | 'source' | 'recyclingKey'
> & {
  /**
   * The outermost native view: the image view itself, or the container
   * around it when `indicator` needs one (always the container in 1.x).
   * Either way it is the view that has `style`, so measuring it gives the
   * image's frame.
   */
  ref?: Ref<TurboImageInstance>;
  source: Source;
  // See the native spec. `null` is accepted and means "no key", so code
  // written for expo-image (`string | null`) compiles unchanged.
  recyclingKey?: string | null;
  cachePolicy?: CachePolicy | LegacyCachePolicy;
  // 1.x also accepted RN's numeric colour form (0xRRGGBBAA); RN's colour
  // processing handles both, Codegen's ColorValue just doesn't spell it.
  monochrome?: ColorValue | number;
  tint?: ColorValue | number;
  // 1.x prop: clip the image to a circle/pill. The image view clips to it
  // itself; toggling it does not remount the view or restart the load.
  rounded?: boolean;
  // 1.x prop: an activity spinner while the image loads. Not shown when a
  // `placeholder` is given (1.x Android's rule; on 1.x iOS whichever prop
  // was set last won).
  indicator?: Indicator;
  /**
   * @deprecated Ignored. 1.x needed it to pick a GIF/APNG/SVG decoder; 2.0
   * detects the format from the image bytes on both platforms.
   */
  format?: Format | string;
  /**
   * @deprecated Ignored, as it effectively was in 1.x: 1.x never enabled
   * progressive decoding in its Nuke pipeline, so the prop had no effect.
   */
  isProgressiveImageRenderingEnabled?: boolean;
};

/** What a `ref` on `<TurboImage>` receives: a native view, as for `<View>`. */
export type TurboImageInstance = ComponentRef<typeof View>;

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

// Maps 1.x's 'dataCache' onto 2.0: it was 1.x iOS's aggressive data cache,
// and 2.0's 'default' is exactly that on both platforms (RFC §4.2).
// 'urlCache' needs no mapping: it is a core policy, and honours HTTP
// Cache-Control on both platforms (1.x did so on iOS only).
let warnedDataCache = false;
function resolveCachePolicy(policy: TurboImageProps['cachePolicy']): CachePolicy | undefined {
  if (policy !== 'dataCache') {
    return policy;
  }
  if (__DEV__ && !warnedDataCache) {
    warnedDataCache = true;
    console.warn(
      "TurboImage: cachePolicy 'dataCache' is deprecated; use 'default' (same behaviour)."
    );
  }
  return 'default';
}

function TurboImageComponent({
  // Taken out of `props` so it goes to one view only. Since React 19 a
  // function component gets `ref` as a prop, and left in the spread below it
  // would always land on the inner image view.
  ref,
  cachePolicy,
  rounded,
  style,
  source,
  // Accepted for 1.x compatibility and dropped; see the type's notes.
  format: _format,
  isProgressiveImageRenderingEnabled: _progressive,
  indicator,
  recyclingKey,
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
  // pick one; failing loudly in development is kinder. Unlike 1.x this does
  // not throw in release builds: a wrong placeholder is not worth a crash.
  //
  // Intentionally omitted: 1.x also threw for `showPlaceholderOnFailure`
  // without a placeholder. That combination is harmless (there is nothing to
  // keep), so 2.0 accepts it. Both are listed under "Breaking changes" in
  // docs/migration-plan.md.
  if (__DEV__ && props.placeholder) {
    const kinds = Object.values(props.placeholder).filter(Boolean).length;
    if (kinds > 1) {
      throw new Error(
        'TurboImage: choose only one placeholder (blurhash, thumbhash or memoryCacheKey)'
      );
    }
  }

  // Only the spinner needs a container: it is a second view over the image.
  // `rounded` is a style on the image view, which clips to its own
  // `borderRadius` on both platforms.
  const needsContainer = showsIndicator;
  const imageStyle = [styles.image, style, rounded && styles.rounded];
  const image = (
    <TurboImageView
      {...(props as Omit<NativeProps, 'cachePolicy' | 'source' | 'recyclingKey'>)}
      ref={needsContainer ? undefined : ref}
      // Codegen strings cannot be null.
      recyclingKey={recyclingKey ?? undefined}
      // A new object each render is fine: both native views compare the
      // request fields by value before reloading.
      source={toNativeSource(source)}
      style={needsContainer ? StyleSheet.absoluteFill : imageStyle}
      cachePolicy={resolveCachePolicy(cachePolicy)}
      // Without an indicator the app's handlers go straight through.
      onStart={showsIndicator ? handleStart : onStart}
      onCompletion={showsIndicator ? handleCompletion : onCompletion}
    />
  );
  if (!needsContainer) {
    return image;
  }
  // As in 1.x, the container takes `style`, `ref` and the rounding (so the
  // spinner is clipped with the image), and `testID` and the accessibility
  // props stay on the image view, which fills the container.
  //
  // The container must not come and go with the spinner: that would remount
  // the native view and restart the load. It does come and go with the
  // `indicator` prop itself, which remounts the image.
  // TODO: draw the spinner natively if toggling `indicator` on a mounted
  // image turns out to matter.
  return (
    <View ref={ref} style={[style, rounded && styles.rounded]}>
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
  // As React Native's <Image>: on iOS a view clips its content to
  // `borderRadius` only with `overflow: 'hidden'`. Without it a rounded
  // <TurboImage> kept square corners there, while Android (which clips in
  // the view's own drawing) rounded them. An app's `overflow: 'visible'`
  // still wins, since `style` comes after this.
  image: { overflow: 'hidden' },
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
  // `dispose` and `clearDiskCache` reject (code 'disk') if the disk cache
  // could not be written to. Android only: iOS stages the removal and has
  // no failure to report.
  dispose: (sources: CacheSource[]): Promise<void> =>
    NativeTurboImageModule.dispose(sources.map(toNativeSource)),
  clearMemoryCache: (): Promise<void> => NativeTurboImageModule.clearMemoryCache(),
  clearDiskCache: (): Promise<void> => NativeTurboImageModule.clearDiskCache(),
});

export default TurboImage;
