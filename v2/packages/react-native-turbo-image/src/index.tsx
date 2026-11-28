import { useEffect, useRef, useState } from 'react';
import type { ComponentRef, Ref } from 'react';
import { ActivityIndicator, Image, StyleSheet, View } from 'react-native';
import type { CodegenTypes, ColorValue } from 'react-native';

import NativeTurboImageModule from './NativeTurboImageModule';
import TurboImageView from './TurboImageViewNativeComponent';
import type {
  FailureEvent as NativeFailureEvent,
  NativeHeader,
  NativePlaceholder,
  NativeProps,
  NativeSource,
  ProgressEvent,
  SuccessEvent,
} from './TurboImageViewNativeComponent';

export type {
  NativePlaceholder as Placeholder,
  ProgressEvent,
  SuccessEvent,
} from './TurboImageViewNativeComponent';

// The values native sends. Codegen types them as plain strings, so they are
// narrowed here, where they reach the app.
/** `onFailure`'s `code` (and `getSize`'s rejection): `turboimage::LoadErrorCode` names. */
export type LoadErrorCode =
  | 'invalidRequest'
  | 'notCached'
  | 'network'
  | 'http'
  | 'decode'
  | 'unknown';
export type StartEvent = Readonly<{ state: 'running' }>;
export type FailureEvent = Readonly<Omit<NativeFailureEvent, 'code'> & { code: LoadErrorCode }>;
export type CompletionEvent = Readonly<{ state: 'completed' | 'cancelled' }>;

// 1.x type names, kept for compatibility. TODO: remove in 3.0.
/** @deprecated Use `StartEvent`. Removed in 3.0. */
export type Start = StartEvent;
/** @deprecated Use `ProgressEvent`. Removed in 3.0. */
export type Progress = ProgressEvent;
/** @deprecated Use `SuccessEvent`. Removed in 3.0. */
export type Success = SuccessEvent;
/** @deprecated Use `FailureEvent`. Removed in 3.0. */
export type Failure = FailureEvent;
/** @deprecated Use `CompletionEvent`. Removed in 3.0. */
export type Completion = CompletionEvent;
export type ResizeMode = NonNullable<NativeProps['resizeMode']>;
/** @deprecated `indicator` is deprecated. Removed in 3.0. */
export type IndicatorStyle = NonNullable<Indicator['style']>;
/** @deprecated `format` is ignored. Removed in 3.0. */
export type Format = 'svg' | 'gif' | 'apng';

// A record, [name, value] pairs, or a fetch `Headers`-like object.
export type HeadersInput =
  | Readonly<Record<string, string>>
  | ReadonlyArray<readonly [string, string]>
  | { forEach(callback: (value: string, name: string) => void): void };

export type RemoteSource = Omit<NativeSource, 'headers'> & { headers?: HeadersInput };

// A URI (http(s), `file://`; on Android also `content://`, `android.resource://`)
// or a bundled asset from `require()`.
export type Source = RemoteSource | number;

// A blurhash, thumbhash, memory-cache key, `{ uri }`, or a `require()` asset.
export type PlaceholderSource = NativePlaceholder | number;

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

function toNativePlaceholder(placeholder: PlaceholderSource | undefined) {
  if (typeof placeholder === 'number') {
    return { uri: Image.resolveAssetSource(placeholder)?.uri ?? '' };
  }
  return placeholder;
}

function toNativeSource(source: Source): NativeSource {
  if (typeof source === 'number') {
    // On Android release this is a bare resource name, resolved natively.
    // An unknown asset id gives an empty URI, which the core rejects.
    return { uri: Image.resolveAssetSource(source)?.uri ?? '' };
  }
  const { headers, ...rest } = source;
  const native = toNativeHeaders(headers);
  return native === undefined ? rest : { ...rest, headers: native };
}

// Defined by the C++ core (cpp/include/turboimage).
export type CachePolicy = NonNullable<NativeProps['cachePolicy']>;

// 1.x policy name, still accepted. TODO: remove in 3.0.
export type LegacyCachePolicy = 'dataCache';

// Like CSS `object-position`: one or two keywords ('bottom right'), or
// percentages from an edge (`{ top: '20%' }`).
// TODO: offsets in points (`{ top: 10 }`), as expo-image takes.
type PositionKeyword = 'center' | 'top' | 'bottom' | 'left' | 'right';
type Percent = `${number}%`;
export type ContentPosition =
  | PositionKeyword
  | `${PositionKeyword} ${PositionKeyword}`
  | { top?: Percent; bottom?: Percent; left?: Percent; right?: Percent };

const KEYWORD_FRACTIONS: Record<PositionKeyword, { x?: number; y?: number }> = {
  center: {},
  top: { y: 0 },
  bottom: { y: 1 },
  left: { x: 0 },
  right: { x: 1 },
};

// '20%' -> 0.2; anything else -> undefined. Accepts exactly what the type
// `${number}%` does (TypeScript's rule: non-empty and `+s` finite), so
// '.5%' and '1e1%' work too.
function percentFraction(value: string | number | undefined): number | undefined {
  if (typeof value === 'string' && value.endsWith('%')) {
    const number = value.slice(0, -1);
    if (number !== '' && Number.isFinite(+number)) {
      return +number / 100;
    }
  }
  if (__DEV__ && value !== undefined) {
    console.warn(
      'TurboImage: contentPosition takes percentages ("20%"); offsets are not supported yet'
    );
  }
  return undefined;
}

// Fractions of the free space; 0.5 = centred.
function toContentPosition(position: ContentPosition | undefined): {
  contentPositionX?: number;
  contentPositionY?: number;
} {
  if (position == null) {
    return {};
  }
  let x = 0.5;
  let y = 0.5;
  if (typeof position === 'string') {
    for (const word of position.trim().split(/\s+/)) {
      const fraction = KEYWORD_FRACTIONS[word as PositionKeyword];
      if (fraction === undefined) {
        if (__DEV__) console.warn(`TurboImage: unknown contentPosition keyword '${word}'`);
        continue;
      }
      x = fraction.x ?? x;
      y = fraction.y ?? y;
    }
  } else {
    const left = percentFraction(position.left);
    const right = percentFraction(position.right);
    const top = percentFraction(position.top);
    const bottom = percentFraction(position.bottom);
    x = left ?? (right === undefined ? x : 1 - right);
    y = top ?? (bottom === undefined ? y : 1 - bottom);
  }
  return { contentPositionX: x, contentPositionY: y };
}

export type TurboImageProps = Omit<
  NativeProps,
  | 'cachePolicy'
  | 'monochrome'
  | 'tint'
  | 'source'
  | 'placeholder'
  | 'recyclingKey'
  | 'contentPositionX'
  | 'contentPositionY'
  | 'progressEnabled'
  | 'loadEventMask'
  | 'onStart'
  | 'onFailure'
  | 'onCompletion'
> & {
  onStart?: CodegenTypes.DirectEventHandler<StartEvent>;
  onFailure?: CodegenTypes.DirectEventHandler<FailureEvent>;
  onCompletion?: CodegenTypes.DirectEventHandler<CompletionEvent>;
  /** The outermost native view (the one with `style`), so measuring it gives the image's frame. */
  ref?: Ref<TurboImageInstance>;
  source: Source;
  placeholder?: PlaceholderSource;
  // Applies to cover, contain, center and scale-down.
  contentPosition?: ContentPosition;
  // `null` means no key (expo-image compatible).
  recyclingKey?: string | null;
  cachePolicy?: CachePolicy | LegacyCachePolicy;
  // Also RN's numeric colour (0xRRGGBBAA), which Codegen's type omits.
  monochrome?: ColorValue | number;
  tint?: ColorValue | number;
  /**
   * Clip to a circle/pill.
   * @deprecated Use `style={{ borderRadius: 9999 }}`. Removed in 3.0.
   */
  rounded?: boolean;
  /**
   * A spinner while loading. Not shown when `placeholder` is set.
   * @deprecated Overlay an `<ActivityIndicator>` driven by `onStart` and
   * `onCompletion`. Removed in 3.0.
   */
  indicator?: Indicator;
  /** @deprecated Ignored; the format is detected from the image bytes. Removed in 3.0. */
  format?: Format | string;
  /** @deprecated Ignored (it had no effect in 1.x either). Removed in 3.0. */
  isProgressiveImageRenderingEnabled?: boolean;
};

/** What a `ref` on `<TurboImage>` receives: a native view, as for `<View>`. */
export type TurboImageInstance = ComponentRef<typeof View>;

/** @deprecated `indicator` is deprecated. Removed in 3.0. */
export type Indicator = {
  style?: 'medium' | 'large';
  color?: ColorValue | number;
};

// Faster loads (cache hits) never show the spinner, which would just flicker.
const INDICATOR_DELAY_MS = 150;

// Each deprecation warns once per app run, in development only.
const warned = new Set<string>();
function warnDeprecated(name: string, advice: string) {
  if (__DEV__ && !warned.has(name)) {
    warned.add(name);
    console.warn(`TurboImage: ${name} is deprecated and will be removed in 3.0; ${advice}.`);
  }
}

// 1.x's 'dataCache' is 2.0's 'default' (RFC §4.2).
function resolveCachePolicy(policy: TurboImageProps['cachePolicy']): CachePolicy | undefined {
  if (policy !== 'dataCache') {
    return policy;
  }
  warnDeprecated("cachePolicy 'dataCache'", "use 'default' (same behaviour)");
  return 'default';
}

function warnDeprecatedProps({
  rounded,
  indicator,
  placeholder,
  format,
  isProgressiveImageRenderingEnabled,
}: Pick<
  TurboImageProps,
  'rounded' | 'indicator' | 'placeholder' | 'format' | 'isProgressiveImageRenderingEnabled'
>) {
  if (rounded != null) {
    warnDeprecated('`rounded`', 'use `style={{ borderRadius: 9999 }}`');
  }
  if (indicator != null) {
    warnDeprecated(
      '`indicator`',
      'overlay an <ActivityIndicator> driven by onStart and onCompletion'
    );
  }
  if (placeholder != null && typeof placeholder === 'object' && placeholder.memoryCacheKey) {
    warnDeprecated('`placeholder.memoryCacheKey`', 'use `placeholder={{ uri }}`');
  }
  if (format != null) {
    warnDeprecated('`format`', 'remove it: the format is detected from the image');
  }
  if (isProgressiveImageRenderingEnabled != null) {
    warnDeprecated('`isProgressiveImageRenderingEnabled`', 'remove it: it has no effect');
  }
}

function TurboImageComponent({
  // Kept out of the spread so it reaches one view only (React 19 ref-as-prop).
  ref,
  cachePolicy,
  rounded,
  style,
  source,
  placeholder,
  contentPosition,
  // Deprecated and ignored.
  format: _format,
  isProgressiveImageRenderingEnabled: _progressive,
  indicator,
  recyclingKey,
  onStart,
  onCompletion,
  ...props
}: TurboImageProps) {
  if (__DEV__) {
    warnDeprecatedProps({
      rounded,
      indicator,
      placeholder,
      format: _format,
      isProgressiveImageRenderingEnabled: _progressive,
    });
  }
  // The spinner is plain React, driven by onStart/onCompletion (every start
  // gets exactly one completion). 1.x quirk: `indicator={{}}` means none.
  // `spinning` tracks the load whenever `indicator` is set, so a placeholder
  // that comes or goes mid-load leaves it right; the placeholder only hides
  // the spinner, since it already shows that something is coming.
  const wantsIndicator = indicator != null && Object.keys(indicator).length > 0;
  const showsIndicator = wantsIndicator && placeholder == null;
  const [spinning, setSpinning] = useState(false);
  const spinTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  useEffect(() => () => clearTimeout(spinTimer.current), []);

  const handleStart: TurboImageProps['onStart'] = (event) => {
    clearTimeout(spinTimer.current);
    spinTimer.current = setTimeout(() => setSpinning(true), INDICATOR_DELAY_MS);
    return onStart?.(event);
  };
  const handleCompletion: TurboImageProps['onCompletion'] = (event) => {
    clearTimeout(spinTimer.current);
    setSpinning(false);
    return onCompletion?.(event);
  };

  // One placeholder kind at a time; throws in development only.
  // `showPlaceholderOnFailure` without a placeholder is harmless, so allowed.
  if (__DEV__ && placeholder != null && typeof placeholder === 'object') {
    const kinds = Object.values(placeholder).filter(Boolean).length;
    if (kinds > 1) {
      throw new Error(
        'TurboImage: choose only one placeholder (blurhash, thumbhash, memoryCacheKey or uri)'
      );
    }
  }

  // Only the spinner needs a container (a second view over the image). It
  // follows `indicator` alone: a placeholder that comes or goes must not
  // remount the image view, which would restart its load.
  const needsContainer = wantsIndicator;
  const imageStyle = [styles.image, style, rounded && styles.rounded];
  const image = (
    <TurboImageView
      {...(props as Omit<NativeProps, 'cachePolicy' | 'source' | 'placeholder' | 'recyclingKey'>)}
      ref={needsContainer ? undefined : ref}
      // Codegen strings cannot be null.
      recyclingKey={recyclingKey ?? undefined}
      // A new object each render is fine: native compares by value.
      source={toNativeSource(source)}
      placeholder={toNativePlaceholder(placeholder)}
      {...toContentPosition(contentPosition)}
      style={needsContainer ? StyleSheet.absoluteFill : imageStyle}
      cachePolicy={resolveCachePolicy(cachePolicy)}
      progressEnabled={props.onProgress != null}
      loadEventMask={loadEventMask(
        wantsIndicator || onStart != null,
        props.onSuccess != null,
        props.onFailure != null,
        wantsIndicator || onCompletion != null
      )}
      // Native sends only the values the narrowed payload types name.
      onStart={(wantsIndicator ? handleStart : onStart) as NativeProps['onStart']}
      onCompletion={
        (wantsIndicator ? handleCompletion : onCompletion) as NativeProps['onCompletion']
      }
    />
  );
  if (!needsContainer) {
    return image;
  }
  // The container takes `style`, `ref` and rounding; `testID` and a11y props
  // stay on the image. It lives as long as `indicator` is set, not just while
  // spinning, since remounting the image would restart the load. It clips as
  // the image view would, since the image inside it has no radius of its own.
  // TODO: draw the spinner natively if toggling `indicator` matters.
  return (
    <View ref={ref} style={imageStyle}>
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
  // iOS clips to `borderRadius` only with `overflow: 'hidden'` (as RN <Image>).
  // An app's own `overflow` still wins.
  image: { overflow: 'hidden' },
  rounded: { overflow: 'hidden', borderRadius: 9999 },
});

// One bit per handled event, in spec order: start, success, failure, completion.
function loadEventMask(...handled: [boolean, boolean, boolean, boolean]): number {
  return handled.reduce((mask, on, bit) => (on ? mask | (1 << bit) : mask), 0);
}

type CacheSource = Source;

/**
 * `TurboImage.prefetch` options. Prefetch downloads to disk only; with no
 * disk tier (`memoryOnly`, a local file) it decodes at full size.
 */
export type PrefetchOptions = {
  /** As the `cachePolicy` prop; `'default'` when unset. */
  cachePolicy?: TurboImageProps['cachePolicy'];
};

/** `TurboImage.configureCache`'s sizes, in bytes; unset keeps the default. */
export type CacheSizes = { maxDiskSize?: number; maxMemoryCost?: number };

// Whole bytes, or 0 for the default.
function cacheBytes(bytes: number | undefined): number {
  return bytes !== undefined && Number.isFinite(bytes) && bytes > 0 ? Math.floor(bytes) : 0;
}

/** What `TurboImage.getSize` resolves with, in pixels. */
export type ImageSize = { width: number; height: number };

// Statics on the component, as in 1.x.
export const TurboImage = Object.assign(TurboImageComponent, {
  // A string second argument is 1.x's cache policy.
  prefetch: (
    sources: CacheSource[],
    optionsOrCachePolicy: PrefetchOptions | TurboImageProps['cachePolicy'] = {}
  ): Promise<boolean> => {
    const options: PrefetchOptions =
      typeof optionsOrCachePolicy === 'object'
        ? optionsOrCachePolicy
        : { cachePolicy: optionsOrCachePolicy };
    return NativeTurboImageModule.prefetch(
      sources.map(toNativeSource),
      resolveCachePolicy(options.cachePolicy ?? 'default') ?? 'default'
    );
  },
  // `dispose` and `clearDiskCache` reject with 'disk' on a disk write error
  // (Android only).
  dispose: (sources: CacheSource[]): Promise<void> =>
    NativeTurboImageModule.dispose(sources.map(toNativeSource)),
  clearMemoryCache: (): Promise<void> => NativeTurboImageModule.clearMemoryCache(),
  clearDiskCache: (): Promise<void> => NativeTurboImageModule.clearDiskCache(),
  /**
   * Sizes the caches in bytes: `maxDiskSize` (default 150 MB) and
   * `maxMemoryCost` (default scales with the device; set only when measured).
   * Call once at startup, before any image or other TurboImage call; returns
   * false, changing nothing, if the caches already exist. On iOS the
   * `urlCache` policy keeps its own 150 MB store.
   */
  configureCache: (sizes: CacheSizes): boolean => {
    const applied = NativeTurboImageModule.configureCache(
      cacheBytes(sizes.maxDiskSize),
      cacheBytes(sizes.maxMemoryCost)
    );
    if (__DEV__ && !applied) {
      console.warn(
        'TurboImage.configureCache: the caches already exist, so the sizes were ignored. Call it at startup, before any image or other TurboImage call.'
      );
    }
    return applied;
  },
  /**
   * The image's size in pixels, EXIF orientation applied, like RN's
   * `Image.getSize`. Caches the image but reads only the file header, not a
   * full decode. Rejects with `onFailure`'s codes.
   */
  getSize: (
    source: CacheSource,
    cachePolicy: TurboImageProps['cachePolicy'] = 'default'
  ): Promise<ImageSize> =>
    NativeTurboImageModule.getSize(
      toNativeSource(source),
      resolveCachePolicy(cachePolicy) ?? 'default'
    ) as Promise<ImageSize>,
});

export default TurboImage;
