// On-device smoke test. Each scenario checks one cross-platform contract
// through the real view and loader. When all settle the screen logs one line,
// which scripts/smoke-{android,ios}.sh wait for:
//   TURBOIMAGE_SMOKE {"pass":true,"passed":N,"total":N,"blocked":N,"failed":{...}}
// The scripts open it with the deep link turboimageexample://smoke on a fresh
// install. Run from the Home screen after other demos, the caches are warm,
// so a failure there is not conclusive: reinstall and use the scripts.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ComponentRef } from 'react';
import {
  Dimensions,
  FlatList,
  PixelRatio,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { TurboImage } from 'react-native-turbo-image';
import type { Source, TurboImageProps } from 'react-native-turbo-image';
import { BASE } from '../fixtures';
import { cacheConfigured } from '../startup';

// Per-run URL tag, so hit counts ignore earlier runs.
const RUN = Date.now().toString(36);

// One 600×400 JPEG under any name; distinct names never share cache entries.
const photo = (name: string) => `${BASE}/photo/${name}.jpg`;
const URI_A = photo('a');
const URI_NEVER_LOADED = photo('never-loaded');
const URI_KEYED_1 = photo('keyed-1');
const URI_KEYED_2 = photo('keyed-2');
// `/slow/` bodies trickle in: several progress events, and time to cancel.
const URI_LIFECYCLE = `${BASE}/slow/photo/lifecycle.jpg`;
const URI_LARGE = `${BASE}/slow/large/superseded.jpg`;
const URI_SMALL = photo('small');
// For the prefetch → dispose chain.
const URI_PREFETCH = photo('prefetch');
// For the processed-variant dispose chain.
const URI_PROCESSED = photo('processed');

// 3000×2000: the downscaling scenarios' source.
const URI_OVERSIZED = `${BASE}/large/oversized.jpg`;

// Cards are 3:2 like the fixtures, so a downscaled decode is the card's pixel size.
const CONTENT_PADDING = 16;
const CARD_WIDTH = Dimensions.get('window').width - 2 * CONTENT_PADDING;
const CARD_WIDTH_PX = CARD_WIDTH * PixelRatio.get();

// A 600×400 photo decodes at its own size, or at the card's on screens
// narrower than 600 px (e.g. CI's 1× emulator).
const PHOTO_SCALE = Math.min(1, CARD_WIDTH_PX / 600);
const PHOTO_DECODED = { width: 600 * PHOTO_SCALE, height: 400 * PHOTO_SCALE };

// `resize` is in points/dp, so the bitmap is this many pixels wide.
const RESIZE_DP = 60;
const RESIZED_PX = Math.round(RESIZE_DP * PixelRatio.get());

// logo.svg: a 120×80 viewBox. One URL per scenario.
const svg = (name: string) => `${BASE}/logo.svg?v=${name}`;
// Drawn for a card: the card's pixel size.
const SVG_IN_CARD = { width: CARD_WIDTH_PX, height: (CARD_WIDTH_PX * 2) / 3 };
// Drawn at its own size: 120×80 points/dp.
const SVG_OWN_SIZE = { width: 120 * PixelRatio.get(), height: 80 * PixelRatio.get() };

type Outcome = 'load' | 'error';
type Settle = (id: string, ok: boolean, outcome: string, detail: string) => void;

type Scenario = {
  id: string;
  title: string;
  // The cache-module probes also pass it to prefetch/dispose.
  source: Source;
  cachePolicy: NonNullable<TurboImageProps['cachePolicy']>;
  // Failing scenarios carry a placeholder: kept with showPlaceholderOnFailure,
  // else blank.
  placeholder?: TurboImageProps['placeholder'];
  showPlaceholderOnFailure?: boolean;
  rounded?: boolean;
  enableLiveTextInteraction?: boolean;
  indicator?: TurboImageProps['indicator'];
  allowHardware?: boolean;
  allowDownscaling?: boolean;
  // Half a card wide, for one image at two sizes.
  halfWidth?: boolean;
  processing?: Pick<TurboImageProps, 'resize' | 'blur' | 'monochrome' | 'tint'>;
  expect: Outcome;
  // Expected loads: the exact onSuccess size in pixels.
  expectSize?: { width: number; height: number };
  // Expected loads: onSuccess size within a few pixels (decoders round differently).
  expectSizeNear?: { width: number; height: number };
  // Expected loads: the URL onSuccess reports.
  expectSource?: string;
  // Expected failures: `onFailure.code`.
  expectCode?: string;
  // getSize probe: the expected result.
  expectGetSize?: { width: number; height: number };
  // urlCache probe: expected server hits after two loads, and how many conditional.
  expectHits?: { count: number; conditional: number };
  // Mount only after these scenarios have settled.
  after?: string | string[];
  // Multi-load scenarios render a probe instead.
  kind?:
    | 'recycle'
    | 'reattach'
    | 'flatList'
    | 'syncReload'
    | 'lifecycle'
    | 'supersede'
    | 'prefetch'
    | 'prefetchInvalid'
    | 'getSize'
    | 'configureCache'
    | 'cookie'
    | 'dispose'
    | 'clearCaches'
    | 'urlCache';
};

const SCENARIOS: Scenario[] = [
  // The two placeholder scenarios come first so screenshots show them.
  {
    id: 'unsupportedScheme',
    title: 'core rejects unsupported schemes',
    source: { uri: 'ftp://example.com/a.png' },
    placeholder: { thumbhash: '4AcKPJpwd3dwd3eHh3eAgAj3iA==' },
    showPlaceholderOnFailure: true,
    cachePolicy: 'default',
    expect: 'error',
    expectCode: 'invalidRequest',
  },
  {
    id: 'cacheMiss',
    title: 'cacheOnly never touches the network',
    source: { uri: URI_NEVER_LOADED },
    placeholder: { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' },
    showPlaceholderOnFailure: true,
    cachePolicy: 'cacheOnly',
    expect: 'error',
    expectCode: 'notCached',
    after: 'network',
  },
  {
    id: 'memoryCacheKeyPlaceholder',
    title: 'memoryCacheKey placeholder shows the photo loaded above',
    // cacheOnly miss; the placeholder is `network`'s image from memory.
    source: { uri: photo('never-loaded-2') },
    placeholder: { memoryCacheKey: URI_A },
    showPlaceholderOnFailure: true,
    cachePolicy: 'cacheOnly',
    expect: 'error',
    expectCode: 'notCached',
    after: 'network',
  },
  {
    id: 'placeholderClearedOnFailure',
    title: 'placeholder removed on failure by default (blank card)',
    source: { uri: 'ftp://example.com/b.png' },
    placeholder: { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' },
    cachePolicy: 'default',
    expect: 'error',
    expectCode: 'invalidRequest',
  },
  {
    id: 'network',
    title: 'default policy loads from network',
    source: { uri: URI_A },
    cachePolicy: 'default',
    expect: 'load',
  },
  {
    id: 'cacheHitCanonicalKey',
    title: 'cacheOnly hits the entry written above (fragment ignored)',
    // Upper-case host and a fragment must canonicalize to `network`'s key.
    source: { uri: URI_A.replace('localhost', 'LOCALHOST') + '#thumb' },
    cachePolicy: 'cacheOnly',
    expect: 'load',
    after: 'network',
  },
  {
    id: 'explicitKeyWrite',
    title: 'explicit cacheKey "shared-key" is written',
    source: { uri: URI_KEYED_1, cacheKey: 'shared-key' },
    cachePolicy: 'default',
    expect: 'load',
  },
  {
    id: 'explicitKeyRead',
    title: 'a different URL with the same cacheKey hits the cache',
    source: { uri: URI_KEYED_2, cacheKey: 'shared-key' },
    cachePolicy: 'cacheOnly',
    expect: 'load',
    after: 'explicitKeyWrite',
  },
  {
    id: 'noCache',
    title: 'noCache always loads from network',
    source: { uri: URI_A },
    cachePolicy: 'noCache',
    expect: 'load',
    after: 'network',
  },
  {
    id: 'recycledSameSource',
    title: 'a recycled view with the same source loads again',
    // Mount, unmount, remount with the same source: the recycled iOS view's
    // stale props once suppressed the reload.
    source: { uri: URI_A },
    cachePolicy: 'default',
    expect: 'load',
    after: 'network',
    kind: 'recycle',
  },
  // Android detaches clipped views; Coil restarts the last request on
  // reattach, which must not refetch or re-report. The hit count checks it.
  {
    id: 'reattachLoaded',
    title: 'a loaded noCache image is not fetched again when reattached',
    source: { uri: `${BASE}/photo/reattach-${RUN}.jpg` },
    cachePolicy: 'noCache',
    expect: 'load',
    expectHits: { count: 1, conditional: 0 },
    kind: 'reattach',
  },
  {
    id: 'reattachFailed',
    title: 'a failed load is not retried when the view is reattached',
    source: { uri: `${BASE}/missing/reattach-${RUN}.jpg` },
    cachePolicy: 'default',
    expect: 'error',
    expectCode: 'http',
    expectHits: { count: 1, conditional: 0 },
    kind: 'reattach',
  },
  {
    id: 'flatListRows',
    title: 'every visible row of a FlatList loads',
    source: { uri: photo('list-row-0') },
    cachePolicy: 'default',
    expect: 'load',
    kind: 'flatList',
  },
  {
    id: 'configureCache',
    title: 'configureCache works at startup and is refused once images exist',
    source: { uri: photo('configure-cache') },
    cachePolicy: 'default',
    expect: 'load',
    after: 'downscaled',
    kind: 'configureCache',
  },
  {
    id: 'getSize',
    title: 'TurboImage.getSize reports 3000×2000 and leaves the image cached',
    source: { uri: `${BASE}/large/get-size.jpg` },
    cachePolicy: 'cacheOnly',
    expect: 'load',
    expectGetSize: { width: 3000, height: 2000 },
    kind: 'getSize',
  },
  {
    // The placeholder's load is silent: one start, success and completion.
    id: 'imagePlaceholder',
    title: 'an image placeholder ({ uri }) while a slow image loads',
    source: { uri: `${BASE}/slow/photo/image-placeholder.jpg` },
    placeholder: { uri: photo('placeholder-thumb') },
    cachePolicy: 'default',
    expect: 'load',
    expectSource: `${BASE}/slow/photo/image-placeholder.jpg`,
  },
  {
    id: 'legacyDataCache',
    title: "1.x cachePolicy 'dataCache' + rounded still work",
    source: { uri: photo('legacy') },
    cachePolicy: 'dataCache',
    rounded: true,
    expect: 'load',
  },
  {
    id: 'prefetchThenCacheOnly',
    title: 'TurboImage.prefetch fills the cache a view then reads',
    source: { uri: URI_PREFETCH },
    cachePolicy: 'cacheOnly',
    expect: 'load',
    kind: 'prefetch',
  },
  {
    id: 'disposeEvicts',
    title: 'TurboImage.dispose evicts it again (cacheOnly misses)',
    source: { uri: URI_PREFETCH },
    cachePolicy: 'cacheOnly',
    expect: 'error',
    expectCode: 'notCached',
    after: 'prefetchThenCacheOnly',
    kind: 'dispose',
  },
  {
    id: 'prefetchInvalid',
    title: 'prefetch of an invalid source resolves false',
    source: { uri: 'ftp://example.com/c.png' },
    cachePolicy: 'default',
    expect: 'error',
    kind: 'prefetchInvalid',
  },
  {
    id: 'clearCaches',
    title: 'clearMemoryCache + clearDiskCache empty both tiers',
    // Written by explicitKeyWrite; after clearing, cacheOnly must miss.
    source: { uri: URI_KEYED_1, cacheKey: 'shared-key' },
    cachePolicy: 'cacheOnly',
    expect: 'error',
    expectCode: 'notCached',
    after: [
      'explicitKeyRead',
      'disposeEvicts',
      'memoryCacheKeyPlaceholder',
      'cacheHitCanonicalKey',
      'recycledSameSource',
      'plainAfterProcessed',
      'disposeEvictsVariants',
      'fullSize',
    ],
    kind: 'clearCaches',
  },
  {
    id: 'processed',
    title: 'resize + tint, served from the shared disk original',
    // Not in memory yet, so it is derived from the original's disk entry.
    source: { uri: URI_A },
    processing: { resize: RESIZE_DP, tint: '#2060c0' },
    cachePolicy: 'cacheOnly',
    expect: 'load',
    expectSize: { width: RESIZED_PX, height: Math.round((RESIZED_PX * 400) / 600) },
    after: 'network',
  },
  {
    id: 'plainAfterProcessed',
    title: 'an unprocessed read still gets the original, not a variant',
    source: { uri: URI_A },
    cachePolicy: 'cacheOnly',
    expect: 'load',
    expectSizeNear: PHOTO_DECODED,
    after: 'processed',
  },
  {
    id: 'processedWrite',
    title: 'blur + monochrome variant is written',
    source: { uri: URI_PROCESSED },
    processing: { blur: 6, monochrome: 'white' },
    cachePolicy: 'default',
    expect: 'load',
  },
  {
    id: 'disposeEvictsVariants',
    title: 'dispose evicts processed variants too (cacheOnly misses)',
    source: { uri: URI_PROCESSED },
    processing: { blur: 6, monochrome: 'white' },
    cachePolicy: 'cacheOnly',
    expect: 'error',
    expectCode: 'notCached',
    after: 'processedWrite',
    kind: 'dispose',
  },
  {
    id: 'downscaled',
    title: 'a 3000×2000 photo is decoded at the card size, not in full',
    source: { uri: URI_OVERSIZED },
    cachePolicy: 'default',
    expect: 'load',
    expectSizeNear: { width: CARD_WIDTH_PX, height: (CARD_WIDTH_PX * 2) / 3 },
  },
  {
    id: 'fullSize',
    title: 'allowDownscaling={false} decodes every pixel, from the disk original',
    // Proves disk kept the original bytes, not the downscaled image.
    source: { uri: URI_OVERSIZED },
    allowDownscaling: false,
    cachePolicy: 'cacheOnly',
    expect: 'load',
    expectSize: { width: 3000, height: 2000 },
    after: 'downscaled',
  },
  // The HTTP cache obeys Cache-Control (RFC §4.2a). Each probe clears the
  // memory cache, so the chain runs after `clearCaches`.
  {
    id: 'urlCache',
    title: 'urlCache: a fresh response is fetched once (max-age)',
    source: { uri: `${BASE}/cache/fresh/${RUN}.jpg` },
    cachePolicy: 'urlCache',
    expect: 'load',
    expectHits: { count: 1, conditional: 0 },
    after: 'clearCaches',
    kind: 'urlCache',
  },
  {
    id: 'urlCacheNoStore',
    title: 'urlCache: no-store is fetched in full every time',
    source: { uri: `${BASE}/cache/nostore/${RUN}.jpg` },
    cachePolicy: 'urlCache',
    expect: 'load',
    expectHits: { count: 2, conditional: 0 },
    after: 'urlCache',
    kind: 'urlCache',
  },
  {
    id: 'urlCacheRevalidate',
    title: 'urlCache: no-cache is revalidated with its ETag (304)',
    source: { uri: `${BASE}/cache/revalidate/${RUN}.jpg` },
    cachePolicy: 'urlCache',
    expect: 'load',
    expectHits: { count: 2, conditional: 1 },
    after: 'urlCacheNoStore',
    kind: 'urlCache',
  },
  {
    id: 'syncReload',
    title: 'memory-cache hits on a mounted view: one completion per start',
    // A, B, A, B on one view: the last two are memory hits that call back
    // inside `load()` on Android, which once looked like a cancel. Runs after
    // the urlCache chain, the last to clear memory.
    source: { uri: photo('sync-a') },
    cachePolicy: 'default',
    expect: 'load',
    after: 'urlCacheRevalidate',
    kind: 'syncReload',
  },
  {
    id: 'liveText',
    title: 'Live Text on an image with text (iOS only; no-op on Android)',
    // Loads with Live Text attached (checks the Swift class lookup).
    source: { uri: `${BASE}/text.png` },
    enableLiveTextInteraction: true,
    cachePolicy: 'default',
    expect: 'load',
  },
  // `/accept/png` returns 406 without the right Accept header. noCache since
  // headers don't key the cache (RFC §4.1).
  {
    id: 'headersSent',
    title: 'source.headers reach the server (Accept: image/png → 200)',
    source: { uri: `${BASE}/accept/png`, headers: { Accept: 'image/png' } },
    cachePolicy: 'noCache',
    expect: 'load',
  },
  {
    // A 200 with a non-image body must be `decode`, not `network`.
    id: 'notAnImage',
    title: 'a 200 that is not an image fails as decode',
    source: { uri: `${BASE}/not-an-image/${RUN}.jpg` },
    cachePolicy: 'noCache',
    expect: 'error',
    expectCode: 'decode',
  },
  {
    id: 'headersChangeResponse',
    title: 'a different header changes the response (Accept: JSON → 406)',
    source: { uri: `${BASE}/accept/png`, headers: [['Accept', 'application/json']] },
    cachePolicy: 'noCache',
    expect: 'error',
    expectCode: 'http',
    // Sequential: concurrent loads of one URL are coalesced, ignoring headers
    // (RFC §4.1).
    after: 'headersSent',
  },
  {
    id: 'headerInjection',
    title: 'a header value with CR/LF is rejected by the core',
    source: { uri: `${BASE}/accept/png`, headers: { 'X-Test': 'a\r\nX-Injected: 1' } },
    cachePolicy: 'noCache',
    expect: 'error',
    expectCode: 'invalidRequest',
  },
  // Formats are detected from the bytes; animation is checked by screenshot.
  {
    id: 'gif',
    title: 'animated GIF',
    source: { uri: `${BASE}/anim.gif` },
    cachePolicy: 'default',
    expect: 'load',
    expectSize: { width: 120, height: 120 },
  },
  {
    id: 'gifDownscaled',
    title: 'a 1500×1000 animated GIF is decoded at the card size too',
    // An animated image's still follows the view size like any other.
    source: { uri: `${BASE}/anim-large.gif` },
    cachePolicy: 'default',
    expect: 'load',
    expectSizeNear: { width: CARD_WIDTH_PX, height: (CARD_WIDTH_PX * 2) / 3 },
  },
  {
    id: 'apng',
    title: 'animated PNG (APNG)',
    source: { uri: `${BASE}/anim.png` },
    cachePolicy: 'default',
    expect: 'load',
    expectSize: { width: 100, height: 100 },
  },
  {
    id: 'webp',
    title: 'animated WebP',
    source: { uri: `${BASE}/anim.webp` },
    cachePolicy: 'default',
    expect: 'load',
    expectSize: { width: 160, height: 120 },
  },
  {
    id: 'svg',
    title: 'SVG (size is the view size on Android, the canvas on iOS)',
    source: { uri: `${BASE}/logo.svg` },
    cachePolicy: 'default',
    expect: 'load',
  },
  {
    id: 'svgFullSize',
    title: 'allowDownscaling={false} does not shrink an SVG to its own size',
    // Original size: Android draws the SVG for the card; iOS keeps the vector
    // and reports its canvas.
    source: { uri: svg('full-size') },
    cachePolicy: 'default',
    allowDownscaling: false,
    expect: 'load',
    ...(Platform.OS === 'android'
      ? { expectSizeNear: SVG_IN_CARD }
      : { expectSize: { width: 120, height: 80 } }),
  },
  {
    id: 'svgTinted',
    title: 'a processed SVG is drawn at the card size before the processor runs',
    // Processing needs pixels, so iOS rasterizes the SVG too.
    source: { uri: svg('tinted') },
    processing: { tint: '#2060c0' },
    cachePolicy: 'default',
    expect: 'load',
    expectSizeNear: SVG_IN_CARD,
  },
  {
    id: 'svgFullSizeTinted',
    title: 'a processed SVG is still drawn at the card size with allowDownscaling={false}',
    source: { uri: svg('full-size-tinted') },
    processing: { tint: '#2060c0' },
    cachePolicy: 'default',
    allowDownscaling: false,
    expect: 'load',
    expectSizeNear: SVG_IN_CARD,
  },
  {
    id: 'svgFullSizeTintedSmaller',
    title: 'the same processed SVG in a smaller view is drawn again for that view',
    // Same cache key as the card above, but no decode size: iOS once handed
    // this view the card-sized bitmap.
    source: { uri: svg('full-size-tinted') },
    processing: { tint: '#2060c0' },
    cachePolicy: 'default',
    allowDownscaling: false,
    halfWidth: true,
    expect: 'load',
    expectSizeNear: { width: SVG_IN_CARD.width / 2, height: SVG_IN_CARD.height / 2 },
    after: 'svgFullSizeTinted',
  },
  {
    id: 'svgBlurred',
    title: 'blur without resize acts on an SVG at its own size in points/dp',
    // `blur` is in image pixels: the view size must not matter, the screen scale must.
    source: { uri: svg('blurred') },
    processing: { blur: 2 },
    cachePolicy: 'default',
    expect: 'load',
    expectSizeNear: SVG_OWN_SIZE,
  },
  {
    id: 'userAgent',
    title: "the User-Agent is not OkHttp's default, which some CDNs refuse",
    // `/ua/` 403s `okhttp/x` like Wikimedia (RFC §4.5b); iOS passes anyway.
    source: { uri: `${BASE}/ua/photo.jpg` },
    cachePolicy: 'default',
    expect: 'load',
  },
  {
    id: 'cookie',
    title: "a cookie set through React Native's fetch: sent on iOS, not on Android",
    // `/cookie/photo/` needs the cookie `fetch` got from `/cookie/set`. iOS
    // shares cookie storage; Android has no cookie jar (RN's would start
    // WebView and delay the first image), so apps pass `source.headers`.
    source: { uri: `${BASE}/cookie/photo/session.jpg` },
    cachePolicy: 'noCache',
    ...(Platform.OS === 'android'
      ? { expect: 'error' as const, expectCode: 'http' }
      : { expect: 'load' as const }),
    kind: 'cookie',
  },
  {
    id: 'requireAsset',
    title: "require()'d bundled asset loads even with cacheOnly",
    // A bundled asset is local, so cacheOnly must still read it.
    source: require('../../assets/local-fixture.png'),
    cachePolicy: 'cacheOnly',
    expect: 'load',
    expectSize: { width: 120, height: 80 },
  },
  {
    id: 'softwareBitmap',
    title: 'allowHardware={false} still loads (Android: software bitmap)',
    // The bitmap config isn't visible from JS; checked once by hand.
    source: { uri: photo('software') },
    allowHardware: false,
    cachePolicy: 'default',
    expect: 'load',
    expectSizeNear: PHOTO_DECODED,
  },
  {
    id: 'indicatorEvents',
    title: 'indicator: app handlers still get every event, in order',
    // The app's own onStart/onCompletion still fire around the spinner.
    source: { uri: `${BASE}/slow/photo/indicator.jpg` },
    indicator: { style: 'large', color: '#e63946' },
    cachePolicy: 'noCache',
    expect: 'load',
    kind: 'lifecycle',
  },
  {
    id: 'lifecycle',
    title: 'events: start → progress… → success → completion',
    source: { uri: URI_LIFECYCLE },
    cachePolicy: 'noCache',
    expect: 'load',
    kind: 'lifecycle',
  },
  {
    id: 'supersede',
    title: 'a superseded load completes as cancelled, never succeeds',
    source: { uri: URI_LARGE },
    cachePolicy: 'noCache',
    expect: 'load',
    kind: 'supersede',
  },
];

// The probes that track a source by URI only ever get URI sources.
const uriOf = (source: Source) => (typeof source === 'number' ? `asset:${source}` : source.uri);

// Fail rather than hang if a callback never arrives.
const TIMEOUT_MS = 45_000;

type Result = { ok: boolean; outcome: string; detail: string };

// --- event recording -------------------------------------------------------

type Recorded =
  | { type: 'start'; source: string }
  | { type: 'progress'; completed: number; total: number }
  | { type: 'success'; source: string }
  | { type: 'failure'; code: string }
  | { type: 'completion'; state: string };

// The five handlers for one <TurboImage>, tagged with its current source.
function recorder(source: string, push: (e: Recorded) => void) {
  return {
    onStart: () => push({ type: 'start', source }),
    onProgress: (e: { nativeEvent: { completed: number; total: number } }) =>
      push({ type: 'progress', ...e.nativeEvent }),
    // Native's `source`: proves which load succeeded despite races.
    onSuccess: (e: { nativeEvent: { source: string } }) =>
      push({ type: 'success', source: e.nativeEvent.source }),
    onFailure: (e: { nativeEvent: { code: string } }) =>
      push({ type: 'failure', code: e.nativeEvent.code }),
    onCompletion: (e: { nativeEvent: { state: string } }) =>
      push({ type: 'completion', state: e.nativeEvent.state }),
  };
}

const describe = (events: Recorded[]) =>
  events
    .map((e) => (e.type === 'completion' ? `completion:${e.state}` : e.type))
    .filter((t, i, all) => t !== 'progress' || all[i - 1] !== 'progress')
    .join(' → ');

// One full successful load: start, monotonic progress, success, completion.
function validateLoad(events: Recorded[]): string | null {
  const types = events.map((e) => e.type);
  if (types[0] !== 'start') return 'first event is not start';
  const last = events[events.length - 1];
  if (last?.type !== 'completion' || last.state !== 'completed')
    return 'does not end with completion:completed';
  if (types[types.length - 2] !== 'success') return 'success is not right before completion';
  const progress = events.filter(
    (e): e is Extract<Recorded, { type: 'progress' }> => e.type === 'progress'
  );
  if (progress.length === 0) return 'no progress events for a network load';
  for (let i = 1; i < progress.length; i++) {
    if (progress[i]!.completed < progress[i - 1]!.completed) return 'progress went backwards';
  }
  const final = progress[progress.length - 1]!;
  if (final.total > 0 && final.completed !== final.total)
    return 'last progress is not completed == total';
  if (types.some((t, i) => t === 'progress' && i > types.indexOf('success')))
    return 'progress after success';
  return null;
}

// --- probes ---------------------------------------------------------------

function LifecycleProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const events = useRef<Recorded[]>([]);
  const push = (e: Recorded) => {
    events.current.push(e);
    if (e.type === 'completion') {
      const problem = validateLoad(events.current);
      settle(scenario.id, problem === null, 'load', problem ?? describe(events.current));
    }
  };
  return (
    <TurboImage
      style={styles.image}
      source={scenario.source}
      cachePolicy={scenario.cachePolicy}
      indicator={scenario.indicator}
      // `push` reads the ref only when an event fires, not during render.
      // oxlint-disable-next-line react/refs
      {...recorder(uriOf(scenario.source), push)}
    />
  );
}

function SupersedeProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const [uri, setUri] = useState(uriOf(scenario.source));
  const events = useRef<Recorded[]>([]);
  const push = (e: Recorded) => {
    events.current.push(e);
    // Swap the source as soon as the first (large) load has started.
    if (e.type === 'start' && e.source === URI_LARGE) {
      setUri(URI_SMALL);
    }
    if (e.type === 'completion' && e.state === 'completed') {
      const all = events.current;
      const cancelAt = all.findIndex((x) => x.type === 'completion' && x.state === 'cancelled');
      let problem: string | null = null;
      if (cancelAt < 0) problem = 'first load did not complete as cancelled';
      else if (all.some((x) => x.type === 'success' && x.source === URI_LARGE))
        problem = 'superseded load reported success';
      else problem = validateLoad(all.slice(cancelAt + 1));
      settle(scenario.id, problem === null, 'load', problem ?? describe(all));
    }
  };
  return (
    <TurboImage
      style={styles.image}
      source={{ uri }}
      cachePolicy={scenario.cachePolicy}
      // `push` reads the ref only when an event fires, not during render.
      // oxlint-disable-next-line react/refs
      {...recorder(uri, push)}
    />
  );
}

function RecycleProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const [phase, setPhase] = useState<'first' | 'gap' | 'second'>('first');
  useEffect(() => {
    if (phase === 'gap') {
      // One empty frame puts the first view in the recycle pool.
      const id = requestAnimationFrame(() => setPhase('second'));
      return () => cancelAnimationFrame(id);
    }
  }, [phase]);
  if (phase === 'gap') {
    return <View style={styles.image} />;
  }
  return (
    <TurboImage
      key={phase}
      style={styles.image}
      source={scenario.source}
      cachePolicy={scenario.cachePolicy}
      onSuccess={(e) =>
        phase === 'first'
          ? setPhase('gap')
          : settle(scenario.id, true, 'load', `${e.nativeEvent.width}×${e.nativeEvent.height}`)
      }
      onFailure={(e) =>
        settle(scenario.id, false, 'error', `${e.nativeEvent.code}: ${e.nativeEvent.error}`)
      }
    />
  );
}

// Time detached, and delay before the sentinel load after reattach.
const DETACHED_MS = 300;
const REATTACHED_MS = 150;

// Load, scroll out of a `removeClippedSubviews` view and back (Android
// detaches it; iOS doesn't), then check one outcome and `expectHits`.
// A sentinel load through the same loader stands in for a fixed wait:
// any stray request reaches the server before it finishes.
function ReattachProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const scroll = useRef<ComponentRef<typeof ScrollView>>(null);
  const outcomes = useRef<string[]>([]);
  const [phase, setPhase] = useState<'loading' | 'away' | 'sentinel' | 'counting'>('loading');
  const onOutcome = (outcome: string) => {
    outcomes.current.push(outcome);
    setPhase((current) => (current === 'loading' ? 'away' : current));
  };
  useEffect(() => {
    if (phase === 'away') {
      scroll.current?.scrollTo({ x: 2 * CARD_WIDTH, animated: false });
      const back = setTimeout(
        () => scroll.current?.scrollTo({ x: 0, animated: false }),
        DETACHED_MS
      );
      const sentinel = setTimeout(() => setPhase('sentinel'), DETACHED_MS + REATTACHED_MS);
      return () => {
        clearTimeout(back);
        clearTimeout(sentinel);
      };
    }
    if (phase === 'counting') {
      const path = uriOf(scenario.source).slice(BASE.length);
      fetch(`${BASE}/__hits?path=${encodeURIComponent(path)}`)
        .then((response) => response.json())
        .then(
          (hits: { count: number }) => {
            const want = scenario.expect === 'load' ? 'load' : `error:${scenario.expectCode}`;
            const saw = `${outcomes.current.join(', ')}; ${hits.count} request(s)`;
            const ok =
              outcomes.current.length === 1 &&
              outcomes.current[0] === want &&
              hits.count === scenario.expectHits?.count;
            settle(scenario.id, ok, scenario.expect, ok ? saw : `${saw}; expected one ${want}`);
          },
          (e) =>
            settle(scenario.id, false, 'error', `could not read the server's request count: ${e}`)
        );
    }
    return undefined;
    // oxlint-disable-next-line react/exhaustive-deps
  }, [phase]);
  return (
    <View>
      <ScrollView
        ref={scroll}
        style={styles.reattachScroll}
        horizontal
        removeClippedSubviews
        scrollEnabled={false}
      >
        {/* A direct child of the content view: only those are clipped. */}
        <TurboImage
          style={styles.reattachImage}
          source={scenario.source}
          cachePolicy={scenario.cachePolicy}
          onSuccess={() => onOutcome('load')}
          onFailure={(e) => onOutcome(`error:${e.nativeEvent.code}`)}
        />
        <View style={styles.reattachFiller} />
      </ScrollView>
      {(phase === 'sentinel' || phase === 'counting') && (
        <TurboImage
          style={styles.sentinel}
          source={{ uri: photo(`sentinel-${scenario.id}-${RUN}`) }}
          cachePolicy="noCache"
          onSuccess={() => setPhase('counting')}
          onFailure={() => setPhase('counting')}
        />
      )}
    </View>
  );
}

// A FlatList clips rows on Android; every visible row must still load
// (a re-parented view once waited for a layout that never came).
const LIST_ROWS = [0, 1, 2].map((row) => photo(`list-row-${row}`));

function FlatListProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const loaded = useRef(new Set<string>());
  return (
    <FlatList
      style={styles.reattachScroll}
      horizontal
      scrollEnabled={false}
      data={LIST_ROWS}
      keyExtractor={(uri) => uri}
      renderItem={({ item: uri }) => (
        <TurboImage
          style={styles.listRow}
          source={{ uri }}
          cachePolicy={scenario.cachePolicy}
          resizeMode="cover"
          onSuccess={() => {
            loaded.current.add(uri);
            if (loaded.current.size === LIST_ROWS.length) {
              settle(scenario.id, true, 'load', `${LIST_ROWS.length} rows`);
            }
          }}
          onFailure={(e) =>
            settle(scenario.id, false, 'error', `${e.nativeEvent.code}: ${e.nativeEvent.error}`)
          }
        />
      )}
    />
  );
}

// One view through four sources, each after the last completes: every
// start gets one completion, never `cancelled`.
const SYNC_RELOAD_SOURCES = [photo('sync-a'), photo('sync-b'), photo('sync-a'), photo('sync-b')];

function SyncReloadProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const [step, setStep] = useState(0);
  const events = useRef<Recorded[]>([]);
  const uri = SYNC_RELOAD_SOURCES[step]!;
  const push = (e: Recorded) => {
    events.current.push(e);
    if (e.type !== 'completion' || e.state !== 'completed') return;
    if (step + 1 < SYNC_RELOAD_SOURCES.length) {
      setStep(step + 1);
      return;
    }
    const all = events.current;
    const count = (type: Recorded['type']) => all.filter((x) => x.type === type).length;
    const succeeded = all.flatMap((x) => (x.type === 'success' ? [x.source] : []));
    let problem: string | null = null;
    if (all.some((x) => x.type === 'completion' && x.state !== 'completed'))
      problem = 'a load that was never superseded did not complete as completed';
    else if (count('start') !== SYNC_RELOAD_SOURCES.length)
      problem = `${count('start')} starts for ${SYNC_RELOAD_SOURCES.length} loads`;
    else if (count('completion') !== count('start'))
      problem = `${count('completion')} completions for ${count('start')} starts`;
    else if (succeeded.join() !== SYNC_RELOAD_SOURCES.join())
      problem = 'the loads did not succeed in the order they were asked for';
    settle(scenario.id, problem === null, 'load', problem ?? describe(all));
  };
  return (
    <TurboImage
      style={styles.image}
      source={{ uri }}
      cachePolicy={scenario.cachePolicy}
      resizeMode="cover"
      // `push` reads the ref only when an event fires, not during render.
      // oxlint-disable-next-line react/refs
      {...recorder(uri, push)}
    />
  );
}

function PlainImage({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  return (
    <TurboImage
      testID={`image-${scenario.id}`}
      style={scenario.halfWidth ? styles.halfImage : styles.image}
      source={scenario.source}
      placeholder={scenario.placeholder}
      showPlaceholderOnFailure={scenario.showPlaceholderOnFailure}
      rounded={scenario.rounded}
      cachePolicy={scenario.cachePolicy}
      enableLiveTextInteraction={scenario.enableLiveTextInteraction}
      indicator={scenario.indicator}
      allowHardware={scenario.allowHardware}
      allowDownscaling={scenario.allowDownscaling}
      {...scenario.processing}
      resizeMode="cover"
      onSuccess={(e) => {
        const { width, height, source } = e.nativeEvent;
        const near = scenario.expectSizeNear;
        const sizeOk =
          (scenario.expectSize === undefined ||
            (width === scenario.expectSize.width && height === scenario.expectSize.height)) &&
          (near === undefined ||
            (Math.abs(width - near.width) <= 2 && Math.abs(height - near.height) <= 2));
        const sourceOk = scenario.expectSource === undefined || source === scenario.expectSource;
        const detail =
          (near && !sizeOk ? ` (expected ≈${near.width}×${near.height})` : '') +
          (sourceOk ? '' : ` from ${source} (expected ${scenario.expectSource})`);
        settle(
          scenario.id,
          scenario.expect === 'load' && sizeOk && sourceOk,
          'load',
          `${width}×${height}${detail}`
        );
      }}
      onFailure={(e) =>
        settle(
          scenario.id,
          scenario.expect === 'error' &&
            (scenario.expectCode === undefined || e.nativeEvent.code === scenario.expectCode),
          'error',
          `${e.nativeEvent.code}: ${e.nativeEvent.error}`
        )
      }
    />
  );
}

// Runs `before`, then a cacheOnly view checked against `expect`/`expectCode`.
function CacheThenView({
  scenario,
  settle,
  before,
}: {
  scenario: Scenario;
  settle: Settle;
  before: () => Promise<boolean>;
}) {
  const [ready, setReady] = useState(false);
  useEffect(() => {
    before().then(
      (ok) =>
        ok ? setReady(true) : settle(scenario.id, false, 'error', 'module call returned false'),
      (e) => settle(scenario.id, false, 'error', `module call rejected: ${e}`)
    );
    // Run once per mount.
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);
  if (!ready) {
    return <View style={styles.image} />;
  }
  return <PlainImage scenario={scenario} settle={settle} />;
}

const PrefetchProbe = (p: { scenario: Scenario; settle: Settle }) => (
  <CacheThenView {...p} before={() => TurboImage.prefetch([p.scenario.source])} />
);

// The startup call must have applied; a call after images exist is refused.
function ConfigureCacheProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  useEffect(() => {
    const later = TurboImage.configureCache({ maxDiskSize: 1 });
    settle(
      scenario.id,
      cacheConfigured && !later,
      'load',
      `startup ${cacheConfigured}, later ${later}`
    );
  }, [scenario.id, settle]);
  return <View style={styles.image} />;
}

// getSize reports the full size and leaves the image on disk, like prefetch.
const GetSizeProbe = (p: { scenario: Scenario; settle: Settle }) => (
  <CacheThenView
    {...p}
    before={() =>
      TurboImage.getSize(p.scenario.source).then(({ width, height }) => {
        const expected = p.scenario.expectGetSize;
        if (expected && (width !== expected.width || height !== expected.height)) {
          throw new Error(`getSize gave ${width}×${height}`);
        }
        return true;
      })
    }
  />
);

const CookieProbe = (p: { scenario: Scenario; settle: Settle }) => (
  <CacheThenView
    {...p}
    before={() => fetch(`${BASE}/cookie/set`, { credentials: 'include' }).then((r) => r.ok)}
  />
);

const DisposeProbe = (p: { scenario: Scenario; settle: Settle }) => (
  <CacheThenView {...p} before={() => TurboImage.dispose([p.scenario.source]).then(() => true)} />
);

const ClearCachesProbe = (p: { scenario: Scenario; settle: Settle }) => (
  <CacheThenView
    {...p}
    before={async () => {
      await TurboImage.clearMemoryCache();
      await TurboImage.clearDiskCache();
      return true;
    }}
  />
);

function PrefetchInvalidProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  useEffect(() => {
    TurboImage.prefetch([scenario.source]).then(
      (ok) => settle(scenario.id, ok === false, 'error', `prefetch resolved ${ok}`),
      (e) => settle(scenario.id, false, 'error', `prefetch rejected: ${e}`)
    );
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);
  return <View style={styles.image} />;
}

// The HTTP cache is its own store (RFC §4.2a). Three loads of one URL:
//   1. `urlCache` loads it;
//   2. memory cleared, `cacheOnly` must miss;
//   3. `urlCache` again: cached, refetched or revalidated per Cache-Control,
//      checked against the server's hit count.
function UrlCacheProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const [phase, setPhase] = useState<'first' | 'clearing' | 'cacheOnly' | 'again' | 'counting'>(
    'first'
  );
  const fail = (what: string) => settle(scenario.id, false, 'error', `${phase}: ${what}`);
  useEffect(() => {
    if (phase === 'clearing') {
      TurboImage.clearMemoryCache().then(
        () => setPhase('cacheOnly'),
        (e) => settle(scenario.id, false, 'error', `clearMemoryCache rejected: ${e}`)
      );
    }
    if (phase === 'counting') {
      const path = uriOf(scenario.source).slice(BASE.length);
      fetch(`${BASE}/__hits?path=${encodeURIComponent(path)}`)
        .then((response) => response.json())
        .then(
          (hits: { count: number; conditional: number }) => {
            const want = scenario.expectHits;
            const ok =
              want !== undefined &&
              hits.count === want.count &&
              hits.conditional === want.conditional;
            const saw = `${hits.count} request(s), ${hits.conditional} conditional`;
            settle(
              scenario.id,
              ok,
              'load',
              ok ? saw : `${saw}; expected ${want?.count}, ${want?.conditional}`
            );
          },
          (e) =>
            settle(scenario.id, false, 'error', `could not read the server's request count: ${e}`)
        );
    }
    // oxlint-disable-next-line react/exhaustive-deps
  }, [phase]);
  if (phase === 'clearing') {
    return <View style={styles.image} />;
  }
  return (
    <TurboImage
      // The image stays mounted while the server is asked.
      key={phase === 'counting' ? 'again' : phase}
      style={styles.image}
      source={scenario.source}
      cachePolicy={phase === 'cacheOnly' ? 'cacheOnly' : 'urlCache'}
      resizeMode="cover"
      onSuccess={() => {
        if (phase === 'first') setPhase('clearing');
        else if (phase === 'cacheOnly') fail('cacheOnly found the image in the keyed disk cache');
        else if (phase === 'again') setPhase('counting');
      }}
      onFailure={(e) => {
        if (phase === 'cacheOnly' && e.nativeEvent.code === 'notCached') setPhase('again');
        else fail(`${e.nativeEvent.code}: ${e.nativeEvent.error}`);
      }}
    />
  );
}

const PROBES = {
  prefetch: PrefetchProbe,
  prefetchInvalid: PrefetchInvalidProbe,
  getSize: GetSizeProbe,
  configureCache: ConfigureCacheProbe,
  dispose: DisposeProbe,
  cookie: CookieProbe,
  clearCaches: ClearCachesProbe,
  recycle: RecycleProbe,
  reattach: ReattachProbe,
  flatList: FlatListProbe,
  syncReload: SyncReloadProbe,
  lifecycle: LifecycleProbe,
  supersede: SupersedeProbe,
  urlCache: UrlCacheProbe,
} as const;

function ScenarioCard({
  scenario,
  result,
  settle,
}: {
  scenario: Scenario;
  result?: Result;
  settle: Settle;
}) {
  const Probe = scenario.kind ? PROBES[scenario.kind] : PlainImage;
  const status = result
    ? `${result.ok ? 'PASS' : 'FAIL'} · ${result.outcome}: ${result.detail}`
    : 'running…';
  return (
    <View style={styles.card}>
      <Text style={styles.label}>
        {scenario.title}
        {'\n'}
        {scenario.cachePolicy} · expect {scenario.expect} · {status}
      </Text>
      <Probe scenario={scenario} settle={settle} />
    </View>
  );
}

// --- app ----------------------------------------------------------------------

export function SmokeTest() {
  const [results, setResults] = useState<Record<string, Result>>({});
  const reported = useRef(false);

  // First settle wins, so a duplicate callback can't flip a result.
  const settle = useCallback<Settle>((id, ok, outcome, detail) => {
    setResults((prev) => (prev[id] ? prev : { ...prev, [id]: { ok, outcome, detail } }));
  }, []);

  const mounted = useMemo(
    () => SCENARIOS.filter((s) => [s.after ?? []].flat().every((dep) => results[dep])),
    [results]
  );
  const settled = Object.keys(results).length === SCENARIOS.length;

  useEffect(() => {
    if (!settled || reported.current) {
      return;
    }
    reported.current = true;
    const pass = Object.values(results).every((r) => r.ok);
    // Compact: iOS os_log truncates at ~1 KB. Blocked scenarios are only
    // counted, so the real failures fit.
    const notOk = Object.entries(results).filter(([, r]) => !r.ok);
    const failed = Object.fromEntries(notOk.filter(([, r]) => r.outcome !== 'blocked'));
    const blocked = notOk.length - Object.keys(failed).length;
    const passed = Object.keys(results).length - notOk.length;
    // iOS release builds drop logs below error level; debug uses console.log
    // to avoid a LogBox toast.
    const report = __DEV__ ? console.log : console.error;
    report(
      `TURBOIMAGE_SMOKE ${JSON.stringify({ pass, passed, total: SCENARIOS.length, blocked, failed })}`
    );
  }, [settled, results]);

  useEffect(() => {
    const timer = setTimeout(() => {
      setResults((prev) => {
        const next = { ...prev };
        for (const s of SCENARIOS) {
          // Never mounted because a prerequisite never settled: say so, not "timeout".
          const waitingFor = [s.after ?? []].flat().filter((dep) => !prev[dep]);
          next[s.id] ??=
            waitingFor.length > 0
              ? {
                  ok: false,
                  outcome: 'blocked',
                  detail: `never ran; waiting for ${waitingFor.join(', ')}`,
                }
              : { ok: false, outcome: 'timeout', detail: '' };
        }
        return next;
      });
    }, TIMEOUT_MS);
    return () => clearTimeout(timer);
  }, []);

  const passed = Object.values(results).filter((r) => r.ok).length;

  return (
    // Light in both appearances: the labels use the default (black) text colour.
    <View style={styles.root}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.title}>TurboImage 2.0 smoke test</Text>
        <Text testID="smoke-summary" style={styles.summary}>
          {settled
            ? `${passed}/${SCENARIOS.length} passed`
            : `running ${Object.keys(results).length}/${SCENARIOS.length}`}
        </Text>
        {mounted.map((scenario) => (
          <ScenarioCard
            key={scenario.id}
            scenario={scenario}
            result={results[scenario.id]}
            settle={settle}
          />
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff' },
  content: { padding: CONTENT_PADDING, gap: 16 },
  title: { fontSize: 20, fontWeight: '600' },
  summary: { fontSize: 15, fontFamily: 'Menlo' },
  card: { gap: 8 },
  label: { fontSize: 12, fontFamily: 'Menlo' },
  image: { width: '100%', aspectRatio: 3 / 2, backgroundColor: '#ddd' },
  halfImage: { width: '50%', aspectRatio: 3 / 2, backgroundColor: '#ddd' },
  // Explicit sizes: a horizontal scroll view can't size an `aspectRatio` child.
  reattachScroll: { width: CARD_WIDTH, height: (CARD_WIDTH * 2) / 3 },
  reattachImage: { width: CARD_WIDTH, height: (CARD_WIDTH * 2) / 3, backgroundColor: '#ddd' },
  // Absolute, so the card keeps its height.
  sentinel: { position: 'absolute', width: 8, height: 8, opacity: 0 },
  listRow: { width: CARD_WIDTH / 3, height: (CARD_WIDTH * 2) / 3, backgroundColor: '#ddd' },
  // Wide enough to scroll the image two card widths out of the clip rect.
  reattachFiller: { width: 3 * CARD_WIDTH },
});
