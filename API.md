# react-native-turbo-image — API

Native image lib: Nuke (iOS) + Coil (Android). Single named export `TurboImage` — React component + static methods (`prefetch`, `clearMemoryCache`, `clearDiskCache`).

```ts
import TurboImage from 'react-native-turbo-image';
```

## Component props

```ts
<TurboImage
  source={{ uri: string, headers?: Record<string,string>, cacheKey?: string }}
  style={ViewStyle}           // required
  resizeMode?: 'contain' | 'cover' | 'stretch' | 'center'  // default 'contain'
  resize?: number             // width in DIP/dp, see Resize below
  cachePolicy?: 'urlCache' | 'dataCache'
  placeholder?: { blurhash } | { thumbhash } | { memoryCacheKey }  // exactly ONE key
  showPlaceholderOnFailure?: boolean   // requires placeholder
  fadeDuration?: number        // ms, default fade-in; disabled if placeholder set
  rounded?: boolean            // circular crop + huge borderRadius on wrapper
  blur?: number                // gaussian blur radius
  monochrome?: number | ColorValue
  tint?: number | ColorValue
  format?: 'svg' | 'gif' | 'apng'
  indicator?: { style: 'large'|'medium', color }
  enableLiveTextInteraction?: boolean   // iOS only, VisionKit
  isProgressiveImageRenderingEnabled?: boolean
  allowHardware?: boolean
  onStart / onProgress / onSuccess / onFailure / onCompletion
/>
```

Throws (JS-side, `TurboImageView.tsx`) if:
- `placeholder` given with `!= 1` keys set.
- `showPlaceholderOnFailure: true` without `placeholder`.

### Events

- `onStart` → `{ state: 'running' }`
- `onProgress` → `{ completed, total }` (bytes)
- `onSuccess` → `{ width, height, source }`
- `onFailure` → `{ error }`
- `onCompletion` → `{ state: 'cancelled' | 'completed' }`

## Resize — how it works

`resize` is a **width-only** downsize processor, not a layout/crop control:

- Value is DIP (iOS) / dp (Android) → converted to px natively (`PixelUtil.toPixelFromDIP` on Android).
- iOS: `ImageProcessors.Resize(width: resize)` (Nuke) — height derived keeping aspect ratio.
- Android: `Size(pxWidth, Dimension.Undefined)` passed to Coil's `ImageRequest.Builder.size()` — height undefined, aspect preserved.
- It's a **processor**, applied before decode/cache-store, so a given `(uri, resize)` combo produces its own distinct cached bitmap — different resize values for the same uri are cached separately (the resize is baked into Nuke's cache key on iOS; on Android it affects the decoded bitmap dimensions but disk cache is keyed by uri/cacheKey only).
- `resizeMode` is separate — it's pure display-time scaling/cropping of the (already resized) bitmap into the view bounds (`contentMode`/`scaleType`), doesn't touch the network fetch or decode size.
- Composed together with `rounded` (circle crop), `blur` (gaussian), `monochrome`, `tint` as an ordered processor pipeline (resize → circle → blur → ... on iOS).

`PrefetchSource.resize` (used only by `prefetch`, see below) behaves the same way — width-only downsize baked into the prefetch request.

## `TurboImage.prefetch(sources, cachePolicy?)`

```ts
prefetch(sources: PrefetchSource[], cachePolicy: CachePolicy = 'urlCache'): Promise<boolean>
```

`PrefetchSource = Source & { resize?: number }`, `Source = { uri, headers?, cacheKey? }`.

- Fires off native image pipeline requests without mounting any view — warms cache ahead of render.
- **iOS**: builds one `ImageRequest` per source (headers + resize processor included), spins up an `ImagePrefetcher` — a fresh `ImagePipeline(configuration: .withDataCache)` if `cachePolicy === 'dataCache'`, else the shared default pipeline (respects HTTP cache headers via `URLCache`). Resolves `true` once `prefetcher.didComplete` fires for *all* requests in that batch.
- **Android**: builds one Coil `ImageRequest` per source (headers + `size()` from resize), using an `ImageLoader` built with `.respectCacheHeaders(cachePolicy == "urlCache")`. Each request enqueued independently; promise resolves `true` once every request's `onSuccess`/`onError` listener has fired (count-based, doesn't reject on individual failures).
- Every prefetched source's `cacheKey ?? uri` gets registered in `TurboImageCacheKeyIndex` (see below) — required so `clear*` prefix filters can find it later.
- `cachePolicy` here only picks which pipeline/loader instance prefetch uses — it's independent from a given `<TurboImage>` view's own `cachePolicy` prop.

## Cache clearing

Both take an optional array mixing two shapes:
- `Source | PrefetchSource` (has `uri`) → clears that exact entry, identified by `cacheKey ?? uri`.
- `PrefixFilter = { include_prefix?, exclude_prefix? }` (no `uri`) → clears every **previously used** key matching prefix rules.

```ts
type PrefixFilter = { include_prefix?: string; exclude_prefix?: string };
clearMemoryCache(sources?: (PrefetchSource | PrefixFilter)[]): Promise<void>;
clearDiskCache(sources?: (Source | PrefixFilter)[]): Promise<void>;
```

Native side distinguishes the two shapes by duck-typing: no `uri` + (`include_prefix` or `exclude_prefix` present) ⇒ treated as a filter.

### No args / empty array → clear everything
- `clearMemoryCache()`: iOS `ImageCache.shared.removeAll()`; Android `Coil.imageLoader(context).memoryCache?.clear()`.
- `clearDiskCache()`: iOS wipes Nuke's data-cache pipeline **and** `URLCache` (covers both cache policies), then `TurboImageCacheKeyIndex.removeAll()`. Android clears Coil's `diskCache` and the same index.

### Explicit sources → targeted removal
Looked up by `cacheKey ?? uri`:
- iOS memory: `ImagePipeline.shared.cache.removeCachedImage(for: request, caches: [.memory])`.
- iOS disk: removes from the data-cache pipeline *and* `DataLoader.sharedUrlCache` (covers whichever `cachePolicy` was originally used).
- Android: `memoryCache?.remove(MemoryCache.Key(...))` / `diskCache?.remove(key)`.

Important: this rebuild of the request/key **never** includes `resize` (`includeResize: false` for all clear-path calls on iOS) — clearing is intentionally keyed by uri/cacheKey identity only, not by a specific resized variant, so one `clearDiskCache` call removes the entry regardless of what resize width was used to fetch it originally.

### Prefix filters → clear by key prefix
Since Nuke/Coil have no "enumerate cached keys" API, the lib keeps its own side index (`TurboImageCacheKeyIndex`, backed by `UserDefaults` on iOS / `SharedPreferences` on Android) of every `cacheKey ?? uri` ever seen via `prefetch` or normal `<TurboImage>` rendering. A filter:

```ts
{ include_prefix: 'https://cdn.example.com/avatars/' }
{ exclude_prefix: 'https://cdn.example.com/tmp/' }
```

resolves against that index (`key.hasPrefix(include)` AND `!key.hasPrefix(exclude)`) to a concrete key list, then each resolved key is removed from cache same as an explicit source, and removed from the index too. Multiple filters in one call are unioned. If both `include_prefix` and `exclude_prefix` are on the same filter object, both apply (AND).

Caveat: the index only knows about keys the app has actually requested/prefetched during its lifetime (persisted across launches via UserDefaults/SharedPreferences) — it's not a scan of whatever happens to be sitting on disk from other sources.

## Types reference (`src/types.ts`)

```ts
type Source = { uri: string; headers?: HeadersInit_; cacheKey?: string };
type PrefetchSource = Source & { resize?: number };
type PrefixFilter = { include_prefix?: string; exclude_prefix?: string };
type CachePolicy = 'urlCache' | 'dataCache';
type ResizeMode = 'contain' | 'cover' | 'stretch' | 'center';
type Format = 'svg' | 'gif' | 'apng';
type Placeholder = { blurhash: string; thumbhash: string; memoryCacheKey: string }; // Partial, pick 1
```
