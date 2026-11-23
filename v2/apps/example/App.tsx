// TurboImage 2.0 example and on-device smoke test.
//
// Each scenario checks one cross-platform contract through the real Fabric
// view and the real Nuke/Coil adapter: cache keys, the cache-policy tier
// matrix, validation, error codes, placeholders, view recycling, and the
// event lifecycle. Scenarios that depend on cache state mount strictly after
// the load they depend on, so outcomes are deterministic.
//
// When every scenario has settled, the app logs exactly one line:
//   TURBOIMAGE_SMOKE {"pass":true,"passed":N,"total":N,"blocked":N,"failed":{...}}
// scripts/smoke-{android,ios}.sh wait for that line in release builds.
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
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { TurboImage } from 'react-native-turbo-image';
import type { TurboImageProps } from 'react-native-turbo-image';

// Every remote fixture comes from scripts/fixture-server.py, which the smoke
// scripts start on the host. The iOS simulator shares the host's loopback;
// the Android emulator reaches it through `adb reverse`. Nothing depends on
// a third-party host, and the server can do what a public one cannot: answer
// by request header, send chosen Cache-Control headers, send slowly, and
// report how many requests actually arrived (`/__hits`).
// The port must match scripts/fixture-server.sh.
const BASE = 'http://localhost:8765';

// Part of the URLs whose requests the server counts, so a count never
// includes an earlier run against a server that was left running.
const RUN = Date.now().toString(36);

// One 600×400 JPEG under any name: a distinct name is a distinct URL, so
// scenarios never share cache entries by accident.
const photo = (name: string) => `${BASE}/photo/${name}.jpg`;
const URI_A = photo('a');
const URI_NEVER_LOADED = photo('never-loaded');
const URI_KEYED_1 = photo('keyed-1');
const URI_KEYED_2 = photo('keyed-2');
// `/slow/` bodies arrive in small timed writes: several progress events for
// the lifecycle scenarios, and a large load that is still downloading when
// JS reacts to onStart, so the supersede scenario can cancel it mid-flight.
const URI_LIFECYCLE = `${BASE}/slow/photo/lifecycle.jpg`;
const URI_LARGE = `${BASE}/slow/large/superseded.jpg`;
const URI_SMALL = photo('small');
// Used only by the cache-module scenarios (prefetch → dispose chain).
const URI_PREFETCH = photo('prefetch');
// Used only by the processed-variant dispose chain.
const URI_PROCESSED = photo('processed');

// 3000×2000, far larger than any card: the downscaling scenarios' source.
const URI_OVERSIZED = `${BASE}/large/oversized.jpg`;

// A card's image is as wide as the window minus the content padding and has
// the 3:2 shape of every photo fixture, so a downscaled decode of a larger
// 3:2 image is exactly the card's size in pixels (give or take rounding).
const CONTENT_PADDING = 16;
const CARD_WIDTH = Dimensions.get('window').width - 2 * CONTENT_PADDING;
const CARD_WIDTH_PX = CARD_WIDTH * PixelRatio.get();

// What a 600×400 photo fixture is decoded to in a card: itself, unless the
// card is narrower than 600 px, in which case the default downscaling brings
// it to the card's size. Phones have cards wider than that, but the default
// emulator on CI has a 320 dp, 1× screen (288 px cards), where expecting
// 600×400 outright failed.
const PHOTO_SCALE = Math.min(1, CARD_WIDTH_PX / 600);
const PHOTO_DECODED = { width: 600 * PHOTO_SCALE, height: 400 * PHOTO_SCALE };

// `resize` is in points/dp and the core converts it with the screen scale,
// so the processed bitmap is this many pixels wide on either platform.
const RESIZE_DP = 60;
const RESIZED_PX = Math.round(RESIZE_DP * PixelRatio.get());

// logo.svg has a 120×80 viewBox and no pixels of its own. Each scenario gets
// its own URL, so none of them reads another's cache entry.
const svg = (name: string) => `${BASE}/logo.svg?v=${name}`;
// Drawn for a card (3:2, like the SVG), it is the card's size in pixels.
const SVG_IN_CARD = { width: CARD_WIDTH_PX, height: (CARD_WIDTH_PX * 2) / 3 };
// Drawn at its own size, 120×80 is read as points/dp.
const SVG_OWN_SIZE = { width: 120 * PixelRatio.get(), height: 80 * PixelRatio.get() };

type Outcome = 'load' | 'error';
type Settle = (id: string, ok: boolean, outcome: string, detail: string) => void;

type Scenario = {
  id: string;
  title: string;
  source: TurboImageProps['source'];
  cachePolicy: NonNullable<TurboImageProps['cachePolicy']>;
  // Failing scenarios carry a placeholder. With showPlaceholderOnFailure it
  // must stay visible after the failure, without it the view must be blank
  // (compare SMOKE_SCREENSHOT output across platforms).
  placeholder?: TurboImageProps['placeholder'];
  showPlaceholderOnFailure?: boolean;
  rounded?: boolean;
  enableLiveTextInteraction?: boolean;
  indicator?: TurboImageProps['indicator'];
  allowHardware?: boolean;
  allowDownscaling?: boolean;
  // Half a card wide (same 3:2 shape), for scenarios about one image shown
  // at two sizes.
  halfWidth?: boolean;
  // Image processors, passed straight through to <TurboImage>.
  processing?: Pick<TurboImageProps, 'resize' | 'blur' | 'monochrome' | 'tint'>;
  expect: Outcome;
  // For expected loads: the exact onSuccess size (in pixels).
  expectSize?: { width: number; height: number };
  // For expected loads: the onSuccess size, within a couple of pixels (the
  // two platforms' decoders round a downscaled size differently).
  expectSizeNear?: { width: number; height: number };
  // For expected failures: the cross-platform `onFailure.code`.
  expectCode?: string;
  // For the urlCache probe: the requests the server must have seen for the
  // source after its two loads, and how many of them were conditional.
  expectHits?: { count: number; conditional: number };
  // Mount only after these scenarios have settled.
  after?: string | string[];
  // Scenarios that need more than one load render a probe instead.
  kind?:
    | 'recycle'
    | 'reattach'
    | 'flatList'
    | 'syncReload'
    | 'lifecycle'
    | 'supersede'
    | 'prefetch'
    | 'prefetchInvalid'
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
    // The source can never load (cacheOnly miss); the placeholder is the
    // `network` scenario's image, taken from the memory cache.
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
    // Upper-case host and a fragment: the core's canonical key must map it
    // to the entry `network` wrote.
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
    // Mounts, unmounts once loaded, remounts with the same source: Fabric on
    // iOS hands back the recycled view, whose stale props used to suppress
    // the reload.
    source: { uri: URI_A },
    cachePolicy: 'default',
    expect: 'load',
    after: 'network',
    kind: 'recycle',
  },
  // A view that scrolls out of a `removeClippedSubviews` list is detached
  // from its window on Android and attached again when it scrolls back. Coil
  // restarts a view's last request on attach, which for a finished load
  // would fetch a noCache image again, or retry a failure JS already heard
  // about. The server's request count shows whether it did.
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
    expectCode: 'network',
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
    // Written by explicitKeyWrite, read by explicitKeyRead; after clearing,
    // a cacheOnly read must miss.
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
    // cacheOnly after `network`: the processed variant is not in memory yet,
    // so this proves it is derived from the original's disk entry.
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
    // cacheOnly after `downscaled`: the full-size image is in neither cache
    // tier as pixels, so this proves the disk kept the original bytes and
    // not the downscaled image.
    source: { uri: URI_OVERSIZED },
    allowDownscaling: false,
    cachePolicy: 'cacheOnly',
    expect: 'load',
    expectSize: { width: 3000, height: 2000 },
    after: 'downscaled',
  },
  // The HTTP cache obeys the response's Cache-Control (RFC §4.2a). Each
  // probe loads its URL twice with the memory cache cleared in between, then
  // asks the server what it saw. Sequential: every probe clears the memory
  // cache, which `memoryCacheKeyPlaceholder` and others read, so the chain
  // starts after `clearCaches`, which already runs after all of those.
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
    // One view, four sources in a row: A, B, A, B. The last two are in the
    // memory cache at this view's size, so on Android the loader calls back
    // before `load()` has returned. That once left a finished load looking
    // in flight, and the next change of source reported it as cancelled.
    // After the urlCache chain, which is the last thing to clear the memory
    // cache: a clear between the steps would turn the hits into fetches.
    source: { uri: photo('sync-a') },
    cachePolicy: 'default',
    expect: 'load',
    after: 'urlCacheRevalidate',
    kind: 'syncReload',
  },
  {
    id: 'liveText',
    title: 'Live Text on an image with text (iOS 16+; no-op on Android)',
    // Asserts the load succeeds with the interaction attached, which
    // exercises the runtime lookup of the Swift class. Whether VisionKit
    // found the text is visible in a screenshot (the Live Text button).
    source: { uri: `${BASE}/text.png` },
    enableLiveTextInteraction: true,
    cachePolicy: 'default',
    expect: 'load',
  },
  // `/accept/png` answers according to the Accept header (406 when it
  // cannot), so the outcome proves the header reached the server. noCache
  // because headers deliberately do not key the cache (RFC §4.1).
  {
    id: 'headersSent',
    title: 'source.headers reach the server (Accept: image/png → 200)',
    source: { uri: `${BASE}/accept/png`, headers: { Accept: 'image/png' } },
    cachePolicy: 'noCache',
    expect: 'load',
  },
  {
    // A 200 whose body is not an image, as a server's HTML error page often
    // is. Android once reported this as `network`: its `ImageDecoder`
    // throws an `IOException` subclass.
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
    expectCode: 'network',
    // Sequential on purpose: concurrent loads of one URL are coalesced on
    // both platforms (Nuke task coalescing, Coil dedup), and headers are not
    // part of that identity any more than of the cache key (RFC §4.1).
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
  // Formats are detected from the bytes (no `format` prop). Whether the
  // animated ones actually play is checked with two screenshots, since no
  // event reports animation.
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
    // The still of an animated image follows the view's size like any other
    // image (an earlier iOS decoder kept every frame at full size). The
    // frames do too, which no event reports.
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
    // A bitmap's original is every pixel; an SVG's would be 120×80, scaled
    // up by the view. Android draws it for the card. iOS keeps the vector
    // image, which reports its canvas and is drawn sharp by the view.
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
    // The core works on pixels, so here iOS needs a bitmap too. It used to
    // be the 120×80 canvas at 1×.
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
    // Same source and processing as the card above, so the same cache key.
    // With allowDownscaling={false} the request carries no decode size, and
    // on iOS the processed bitmap's memory key had no size in it either:
    // this view was handed the card-sized bitmap.
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
    // `blur` is in image pixels, so the view's size must not matter; the
    // screen's scale does, or the SVG would be a third of its size on a 3×
    // screen and the blur three times as strong.
    source: { uri: svg('blurred') },
    processing: { blur: 2 },
    cachePolicy: 'default',
    expect: 'load',
    expectSizeNear: SVG_OWN_SIZE,
  },
  {
    id: 'userAgent',
    title: "the User-Agent is not OkHttp's default, which some CDNs refuse",
    // `/ua/` answers 403 to `okhttp/x`, as Wikimedia does (RFC §4.5b). iOS
    // sends CFNetwork's User-Agent and passes either way.
    source: { uri: `${BASE}/ua/photo.jpg` },
    cachePolicy: 'default',
    expect: 'load',
  },
  {
    id: 'cookie',
    title: "a cookie set through React Native's fetch: sent on iOS, not on Android",
    // `/cookie/set` answers the app's `fetch` with Set-Cookie, as a login
    // endpoint would; `/cookie/photo/` answers 403 without that cookie. iOS
    // shares `HTTPCookieStorage` between the two, so the image loads. The
    // Android client has no cookie jar, as in 1.x: React Native's store
    // starts WebView on first use, which held up a process's first network
    // image by 0.2–0.6 s. Apps pass a session in `source.headers` instead.
    // noCache, so the request is made on every run.
    source: { uri: `${BASE}/cookie/photo/session.jpg` },
    cachePolicy: 'noCache',
    ...(Platform.OS === 'android'
      ? { expect: 'error' as const, expectCode: 'network' }
      : { expect: 'load' as const }),
    kind: 'cookie',
  },
  {
    id: 'requireAsset',
    title: "require()'d bundled asset loads even with cacheOnly",
    // Release builds resolve this to a file:// bundle URL on iOS and to a
    // resource name on Android (mapped to android.resource://). Local
    // sources are not "network", so cacheOnly must still read them.
    source: require('./assets/local-fixture.png'),
    cachePolicy: 'cacheOnly',
    expect: 'load',
    expectSize: { width: 120, height: 80 },
  },
  {
    id: 'softwareBitmap',
    title: 'allowHardware={false} still loads (Android: software bitmap)',
    // The bitmap's config is not visible from JS; it was checked once with
    // a temporary log (HARDWARE by default, ARGB_8888 with this prop).
    source: { uri: photo('software') },
    allowHardware: false,
    cachePolicy: 'default',
    expect: 'load',
    expectSizeNear: PHOTO_DECODED,
  },
  {
    id: 'indicatorEvents',
    title: 'indicator: app handlers still get every event, in order',
    // The spinner is driven by onStart/onCompletion inside <TurboImage>;
    // this checks the app's own handlers are still called around it. That
    // the spinner is drawn was checked by screenshot on a slow load.
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
const uriOf = (source: TurboImageProps['source']) =>
  typeof source === 'number' ? `asset:${source}` : source.uri;

// Fail rather than hang if a callback never arrives (e.g. a lost event).
const TIMEOUT_MS = 45_000;

type Result = { ok: boolean; outcome: string; detail: string };

// --- event recording -------------------------------------------------------

type Recorded =
  | { type: 'start'; source: string }
  | { type: 'progress'; completed: number; total: number }
  | { type: 'success'; source: string }
  | { type: 'failure'; code: string }
  | { type: 'completion'; state: string };

// Builds the five handlers for one <TurboImage>, tagging every event with
// the source the element had when it fired.
function recorder(source: string, push: (e: Recorded) => void) {
  return {
    onStart: () => push({ type: 'start', source }),
    onProgress: (e: { nativeEvent: { completed: number; total: number } }) =>
      push({ type: 'progress', ...e.nativeEvent }),
    // The native `source` field, not the JS-side URI: proves *which* load
    // succeeded even if a late callback raced a source change.
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

// Validates one complete, successful load: start, monotonic progress that
// ends at completed == total (when total is known), success, completion.
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
      // `push` reads the ref, but only when an event fires: `recorder` wraps
      // it in handlers and never calls it during render.
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
      // `push` reads the ref, but only when an event fires: `recorder` wraps
      // it in handlers and never calls it during render.
      // oxlint-disable-next-line react/refs
      {...recorder(uri, push)}
    />
  );
}

function RecycleProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const [phase, setPhase] = useState<'first' | 'gap' | 'second'>('first');
  useEffect(() => {
    if (phase === 'gap') {
      // One frame with nothing mounted puts the first view in the recycle pool.
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

// How long a detached view stays detached, and how long after it is back
// the sentinel load starts (the scroll that reattaches it is a native
// command, so "back" is a few frames after the call).
const DETACHED_MS = 300;
const REATTACHED_MS = 150;

// Loads the scenario's source, scrolls the image out of a
// `removeClippedSubviews` scroll view and back, then checks that the load
// reported exactly one outcome and the server saw `expectHits` requests.
// Android removes the clipped image from its parent, which detaches it from
// the window; iOS keeps it attached, so there this is a plain load.
//
// "No second request" is not judged by waiting a fixed time. Once the image
// is back, a sentinel image is loaded through the same loader; a request the
// reattach should not have made was started before the sentinel's, so it has
// reached the server by the time the sentinel's load has finished.
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

// A real FlatList, which clips its rows' views on Android by default
// (`removeClippedSubviews`). Every visible row must load: a row's view that
// was taken out of its parent and put back before its load could size itself
// used to wait for a layout pass that never came.
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

// One mounted view through four sources, each set when the one before has
// completed. Nothing is ever superseded, so every start must be answered by
// exactly one completion, and none of them may say `cancelled`.
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
      // `push` reads the ref, but only when an event fires: `recorder` wraps
      // it in handlers and never calls it during render.
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
        const { width, height } = e.nativeEvent;
        const near = scenario.expectSizeNear;
        const sizeOk =
          (scenario.expectSize === undefined ||
            (width === scenario.expectSize.width && height === scenario.expectSize.height)) &&
          (near === undefined ||
            (Math.abs(width - near.width) <= 2 && Math.abs(height - near.height) <= 2));
        const detail = near && !sizeOk ? ` (expected ≈${near.width}×${near.height})` : '';
        settle(
          scenario.id,
          scenario.expect === 'load' && sizeOk,
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

// Runs `before` (a cache-module call), then mounts a cacheOnly view of the
// scenario's source and checks the outcome against `expect`/`expectCode`.
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

// The HTTP cache is a store of its own (RFC §4.2a). Three loads of one URL:
//   1. `urlCache` loads it (network; stored in the HTTP cache if allowed);
//   2. with the memory cache cleared, `cacheOnly` must miss: the keyed disk
//      cache was never written;
//   3. `urlCache` loads it again: from the HTTP cache, from the network, or
//      revalidated, depending on the response's Cache-Control.
// Which of those step 3 was is not visible in the events, so the probe then
// asks the fixture server what it received (`expectHits`).
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

export default function App() {
  const [results, setResults] = useState<Record<string, Result>>({});
  const reported = useRef(false);

  // First settle wins: a duplicate callback (e.g. a restarted Coil request
  // after reattach) must not flip a settled result.
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
    // Compact on purpose: iOS os_log truncates messages at ~1 KB, which cut
    // the full results off mid-JSON. Details are only needed for failures.
    // Blocked scenarios are only counted: their cause is one of the listed
    // failures, and listing them would push that cause past the 1 KB cut.
    const notOk = Object.entries(results).filter(([, r]) => !r.ok);
    const failed = Object.fromEntries(notOk.filter(([, r]) => r.outcome !== 'blocked'));
    const blocked = notOk.length - Object.keys(failed).length;
    const passed = Object.keys(results).length - notOk.length;
    // Release builds on iOS drop everything below RCTLogLevelError, and the
    // smoke scripts run release builds, so the result has to go out as an
    // error there. Debug keeps console.log to avoid a LogBox error toast.
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
          // A scenario whose prerequisites never settled was never mounted.
          // Reporting it as a timeout once made hung network loads look
          // like hung cache reads, so say which it is. Judged against
          // `prev`: only what settled before the deadline counts.
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
    <SafeAreaProvider>
      <SafeAreaView style={styles.root}>
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
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: CONTENT_PADDING, gap: 16 },
  title: { fontSize: 20, fontWeight: '600' },
  summary: { fontSize: 15, fontFamily: 'Menlo' },
  card: { gap: 8 },
  label: { fontSize: 12, fontFamily: 'Menlo' },
  image: { width: '100%', aspectRatio: 3 / 2, backgroundColor: '#ddd' },
  halfImage: { width: '50%', aspectRatio: 3 / 2, backgroundColor: '#ddd' },
  // Explicit sizes: a horizontal scroll view has no height of its own to
  // give an `aspectRatio` child.
  reattachScroll: { width: CARD_WIDTH, height: (CARD_WIDTH * 2) / 3 },
  reattachImage: { width: CARD_WIDTH, height: (CARD_WIDTH * 2) / 3, backgroundColor: '#ddd' },
  // Out of the layout, so the card keeps its height when it appears.
  sentinel: { position: 'absolute', width: 8, height: 8, opacity: 0 },
  listRow: { width: CARD_WIDTH / 3, height: (CARD_WIDTH * 2) / 3, backgroundColor: '#ddd' },
  // Wide enough to scroll the image two card widths out of the clip rect.
  reattachFiller: { width: 3 * CARD_WIDTH },
});
