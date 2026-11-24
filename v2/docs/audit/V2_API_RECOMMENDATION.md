# TurboImage v2: API recommendation

Companion to [`V2_ARCHITECTURE_AUDIT.md`](V2_ARCHITECTURE_AUDIT.md) and
[`V2_SIMPLIFICATION_PLAN.md`](V2_SIMPLIFICATION_PLAN.md). The current surface
is read from `pkg/src/index.tsx`, `pkg/src/TurboImageViewNativeComponent.ts`
and `pkg/src/NativeTurboImageModule.ts` (`pkg/` stands for
`v2/packages/react-native-turbo-image/`).

## Classification

| Class | Meaning |
|---|---|
| **Core** | Essential to an image component |
| **Valuable** | Meaningful differentiation |
| **Optional** | Useful for a subset of users |
| **Redundant** | Covered by another API |
| **Remove** | Complexity without enough value |
| **Defer** | Not for 2.0 |

"1.x" means the prop existed in 1.x, so removing it has a migration cost.

### Props

| Prop | Origin | Class | Recommendation |
|---|---|---|---|
| `source: { uri, headers?, cacheKey? }` | 1.x | Core | Keep |
| `source: number` (`require()`) | 2.0 | Core | Keep. Parity with `<Image>` |
| `source: SizedSource[]` (source sets) | 2.0 | Defer | Remove before 2.0.0 (plan S7) |
| `source.headers` (record, pairs, `Headers`) | 1.x | Core | Keep all three forms. The normalisation is 20 lines of JS |
| `source.cacheKey` | 1.x | Core | Keep. Needed for rotating signed URLs |
| `cachePolicy` `'default' \| 'memoryOnly' \| 'noCache' \| 'cacheOnly'` | 2.0 names | Core | Keep |
| `cachePolicy='urlCache'` | 1.x | Optional | Keep. 1.x compatibility, and the only HTTP-freshness option |
| `cachePolicy='dataCache'` | 1.x | Redundant | Alias of `'default'`; warn; remove in 3.0 |
| `placeholder: { blurhash }`, `{ thumbhash }` | 1.x | Valuable | Keep |
| `placeholder: { uri }` / `number` | 2.0 | Valuable | Keep; the recommended general form |
| `placeholder: { memoryCacheKey }` | 1.x | Redundant (mostly) | Keep in 2.x; document `{ uri }` as preferred; remove in 3.0 |
| `showPlaceholderOnFailure` | 1.x | Optional | Keep |
| `resizeMode` `cover \| contain \| stretch \| center` | 1.x | Core | Keep. Note that the default `contain` differs from `<Image>`'s `cover` (1.x compatibility) |
| `resizeMode='scale-down'` | 2.0 | Optional | Keep. Cheap, and expo-image parity |
| `contentPosition` | 2.0 | Optional | Keep as implemented; no point offsets in 2.0 |
| `recyclingKey` | 2.0 | Valuable | Keep. Required for correct FlashList reuse |
| `allowDownscaling` | 2.0 | Valuable | Keep. The default-on memory win, with silent upgrades |
| `fadeDuration` | 1.x | Core | Keep |
| `resize` | 1.x | Optional | Keep. Decoding to the view's size covers its old main use; it is still useful to share one memory entry across sizes and to pair with `blur` |
| `blur` | 1.x | Valuable | Keep |
| `tint` | 1.x | Valuable | Keep (icons) |
| `monochrome` | 1.x | Optional | Keep. Costs one function in the core |
| `allowHardware` (Android) | 1.x | Optional | Keep; document as platform-specific |
| `enableLiveTextInteraction` (iOS) | 1.x | Optional | Keep; document as platform-specific |
| `rounded` | 1.x | Redundant | It is `borderRadius: 9999`; warn; remove in 3.0 |
| `indicator` | 1.x | Optional | Keep in 2.x; warn; remove in 3.0 (it forces a container, ADR 0009) |
| `format` | 1.x | Remove | Already ignored; deprecated type; delete in 3.0 |
| `isProgressiveImageRenderingEnabled` | 1.x | Remove | Already ignored; delete in 3.0 |
| `progressEnabled`, `loadEventMask` | internal | n/a | Not public. `loadEventMask` stays only if measured (plan S12) |

### Events

| Event | Class | Recommendation |
|---|---|---|
| `onStart` | Core | Keep |
| `onProgress` | Optional | Keep. It already costs nothing without a handler (`progressEnabled`) |
| `onSuccess { width, height, source }` | Core | Keep. Documented as the *decoded* size |
| `onFailure { code, error }` | Core | Keep. `code` is the stable contract; `error` is diagnostic |
| `onCompletion { state }` | Core | Keep. It ends every load, including `'cancelled'` |

The names follow 1.x, not React Native's `onLoadStart`/`onLoad`/`onError`/
`onLoadEnd`. Keep them. Adding aliases would double the surface for no new
capability.

### Statics (TurboModule)

| Static | Origin | Class | Recommendation |
|---|---|---|---|
| `TurboImage.prefetch(sources, cachePolicy?)` | 1.x | Core | Keep |
| `prefetch(sources, { cachePolicy })` | 2.0 | Core | Keep the options object |
| `prefetch(…, { resize: number \| 'original' })` | 2.0 | Remove | Disk-only prefetch (plan S6) |
| `TurboImage.dispose(sources)` | 1.x (never worked) | Valuable | Keep |
| `TurboImage.clearMemoryCache()` / `clearDiskCache()` | 1.x | Core | Keep |
| `TurboImage.getSize(source, cachePolicy?)` | 2.0 | Valuable | Keep. `Image.getSize` parity, reading only the header |
| `TurboImage.configureCache({ maxDiskSize, maxMemoryCost })` | 2.0 | Optional | Keep. Startup-only and synchronous, as documented |

### Types

| Export | Recommendation |
|---|---|
| `TurboImageProps`, `Source`, `RemoteSource`, `PlaceholderSource`, `HeadersInput`, `CachePolicy`, `ResizeMode`, `ContentPosition`, `ImageSize`, `CacheSizes`, `PrefetchOptions`, `TurboImageInstance` | Keep |
| `StartEvent`, `ProgressEvent`, `SuccessEvent`, `FailureEvent`, `CompletionEvent`, `Placeholder` | Keep |
| `SizedSource` | Remove with source sets |
| `Start`, `Progress`, `Success`, `Failure`, `Completion`, `LegacyCachePolicy`, `Format`, `IndicatorStyle`, `Indicator` | 1.x aliases. Keep in 2.x, mark `@deprecated`, remove in 3.0 |

### Native extension points

| API | Recommendation |
|---|---|
| `TIImageLoaderRegistry.sharedLoader` setter (iOS) | Make it not public (plan S1) |
| `TurboImageLoaders.set` (Android) | `internal` / `@VisibleForTesting` (plan S1) |
| `TIImageLoading`, `ImageLoaderAdapter` | Internal structure, not a supported public contract |

---

## Recommended 2.0 public API

```ts
import type { ColorValue, ViewProps } from 'react-native';

type HeadersInput =
  | Readonly<Record<string, string>>
  | ReadonlyArray<readonly [string, string]>
  | { forEach(cb: (value: string, name: string) => void): void };

type Source = { uri: string; headers?: HeadersInput; cacheKey?: string } | number;

type PlaceholderSource =
  | { blurhash: string }
  | { thumbhash: string }
  | { uri: string }
  | number
  /** @deprecated Use `{ uri }`. Removed in 3.0. */
  | { memoryCacheKey: string };

type CachePolicy = 'default' | 'memoryOnly' | 'noCache' | 'cacheOnly' | 'urlCache';
type ResizeMode = 'cover' | 'contain' | 'stretch' | 'center' | 'scale-down';

type TurboImageProps = ViewProps & {
  // What to load
  source: Source;
  cachePolicy?: CachePolicy; // default 'default'

  // What to show meanwhile
  placeholder?: PlaceholderSource;
  showPlaceholderOnFailure?: boolean;
  recyclingKey?: string | null;
  fadeDuration?: number; // ms, default 300

  // How to draw it
  resizeMode?: ResizeMode; // default 'contain' (1.x)
  contentPosition?: ContentPosition;
  allowDownscaling?: boolean; // default true

  // Pixel processing (shared C++ core, identical on both platforms)
  resize?: number;
  blur?: number;
  tint?: ColorValue;
  monochrome?: ColorValue;

  // Platform-specific
  allowHardware?: boolean; // Android only
  enableLiveTextInteraction?: boolean; // iOS only

  // Events: onStart → onProgress* → (onSuccess | onFailure) → onCompletion
  onStart?: (e: { nativeEvent: StartEvent }) => void;
  onProgress?: (e: { nativeEvent: ProgressEvent }) => void;
  onSuccess?: (e: { nativeEvent: SuccessEvent }) => void;
  onFailure?: (e: { nativeEvent: FailureEvent }) => void;
  onCompletion?: (e: { nativeEvent: CompletionEvent }) => void;

  /** @deprecated `style={{ borderRadius: 9999 }}`. Removed in 3.0. */
  rounded?: boolean;
  /** @deprecated Overlay an `<ActivityIndicator>` from onStart/onCompletion. Removed in 3.0. */
  indicator?: { style?: 'medium' | 'large'; color?: ColorValue };
  /** @deprecated Ignored. Removed in 3.0. */
  format?: string;
  /** @deprecated Ignored. Removed in 3.0. */
  isProgressiveImageRenderingEnabled?: boolean;
};

declare const TurboImage: React.FC<TurboImageProps> & {
  prefetch(sources: Source[], options?: { cachePolicy?: CachePolicy } | CachePolicy): Promise<boolean>;
  dispose(sources: Source[]): Promise<void>;
  clearMemoryCache(): Promise<void>;
  clearDiskCache(): Promise<void>;
  getSize(source: Source, cachePolicy?: CachePolicy): Promise<{ width: number; height: number }>;
  configureCache(sizes: { maxDiskSize?: number; maxMemoryCost?: number }): boolean;
};
```

Compared with today:

- **No `source` array.**
- **No `prefetch` `resize` option.**
- **The deprecations are explicit.** Everything else is unchanged.

---

## Essential vs optional

**Essential:** the smallest set an app needs to replace `<Image>` in a list.

- `source` (with `headers`, `cacheKey`, `require()`)
- `cachePolicy`
- `placeholder` (hash or `uri`)
- `recyclingKey`
- `resizeMode`
- `fadeDuration`
- the five events
- `prefetch`, `clearMemoryCache`, `clearDiskCache`

**Valuable defaults that need no configuration:** decode-to-view-size with silent upgrades, synchronous memory hits, request coalescing, and one isolated cache per process.

**Optional:**

- `contentPosition`, `scale-down`
- `resize`, `blur`, `tint`, `monochrome`
- `urlCache`
- `getSize`, `dispose`, `configureCache`
- `allowHardware`, `enableLiveTextInteraction`
- `showPlaceholderOnFailure`
- `onProgress`

---

## Compatibility considerations

1. **2.0 is the window for removals.** Everything new in 2.0 (source sets, `prefetch` `resize`) can be cut at no migration cost before `2.0.0`. Every 1.x prop stays through 2.x.
2. **Deprecation mechanics.** Mirror the existing `dataCache` pattern:
   - a one-time `console.warn` in `__DEV__`,
   - `@deprecated` JSDoc,
   - an entry in `migration-guide.md`,
   - removal in 3.0.
3. **Behaviour changes are already documented** (`migration-plan.md`, "Breaking changes"). The two most likely to surprise apps:
   - `onSuccess` reports the *decoded* size, not the source size.
   - The previous image stays up on a source change unless `recyclingKey` changes.

   Both deserve a top-of-guide callout, not a list entry.
4. **Platform-specific props** (`allowHardware`, `enableLiveTextInteraction`) are no-ops on the other platform, as in 1.x. Keep that; do not throw.
5. **Defaults that differ from `<Image>`:**
   - `resizeMode='contain'` (vs `'cover'`),
   - `fadeDuration=300` (`<Image>` on Android: 300; iOS: none).

   Keeping 1.x defaults is the right call for a 1.x → 2.x migration. Revisit in 3.0, not now.
6. **`ref`** targets the image view unless `indicator` is set. Removing `indicator` in 3.0 makes it always the image view, which resolves ADR 0009's open question.
