// Every remote image in the example comes from scripts/fixture-server.py,
// started on the host with `bun run fixtures` (v2/). A local server instead
// of a public CDN, because:
//   - runs are reproducible, offline, and never rate-limited;
//   - it can do what the demos need: refuse a header, revalidate with an
//     ETag, trickle a body slowly, return a non-image, and count requests
//     (`/__hits`), which is how the Performance screen measures reuse.
// Android reaches it through `adb reverse tcp:8765 tcp:8765` (the script sets
// that up). A physical iPhone cannot reach the host's localhost: point BASE
// at the Mac's LAN address and start the server with `--host 0.0.0.0`.
// TODO: read BASE from the launch URL, so a device run needs no code edit.
import type { CachePolicy, Source } from 'react-native-turbo-image';

// Must match fixture_server_port in scripts/fixture-server.sh.
export const BASE = 'http://localhost:8765';

// The server returns one 600×400 (or 3000×2000) JPEG under any name. Distinct
// names are distinct URLs and so distinct cache entries. Demo names start
// with `demo-` so they never share an entry with a smoke-test scenario.
export const photoUrl = (name: string) => `${BASE}/photo/demo-${name}.jpg`;
export const largeUrl = (name: string) => `${BASE}/large/demo-${name}.jpg`;
// About 2 s per image, so placeholders, progress and cancellation are visible.
export const slowLargeUrl = (name: string) => `${BASE}/slow/large/demo-${name}.jpg`;

// Sample hashes (the smoke test uses them too); any valid hash works.
export const BLURHASH = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
export const THUMBHASH = '4AcKPJpwd3dwd3eHh3eAgAj3iA==';

export type DemoSource = {
  id: string;
  label: string;
  source: Source;
  // What to look for: shown under the image on the Detail screen.
  note: string;
  // The policy the demo needs to show its point; the Detail screen starts
  // with it and the viewer can still change it.
  cachePolicy?: CachePolicy;
};

// The sources the Detail screen and the Playground offer, in display order.
export const DEMO_SOURCES: DemoSource[] = [
  {
    id: 'photo',
    label: 'Photo',
    source: { uri: photoUrl('photo') },
    note: 'A 600×400 JPEG. The second load is a memory-cache hit: no progress, no fade.',
  },
  {
    id: 'large',
    label: '3000×2000',
    source: { uri: largeUrl('large') },
    note: 'Decoded no larger than the view (allowDownscaling). onSuccess reports the decoded size, not 3000×2000.',
  },
  {
    id: 'slow',
    label: 'Slow',
    source: { uri: slowLargeUrl('slow') },
    note: 'Trickles in over about 2 s: many onProgress events. Cached after the first load, so pick noCache or clear the caches to see it again.',
    cachePolicy: 'noCache',
  },
  {
    id: 'local',
    label: 'Bundled',
    source: require('../assets/local-fixture.png'),
    note: "A require()'d asset, 120×80. Local, so it loads even with cacheOnly.",
  },
  {
    id: 'gif',
    label: 'GIF',
    source: { uri: `${BASE}/anim.gif` },
    note: 'Animated GIF. The format is detected from the bytes; no `format` prop.',
  },
  {
    id: 'apng',
    label: 'APNG',
    source: { uri: `${BASE}/anim.png` },
    note: 'Animated PNG.',
  },
  {
    id: 'webp',
    label: 'WebP',
    source: { uri: `${BASE}/anim.webp` },
    note: 'Animated WebP.',
  },
  {
    id: 'svg',
    label: 'SVG',
    source: { uri: `${BASE}/logo.svg` },
    note: 'SVG. onSuccess reports the view size on Android (drawn for the view) and the canvas size on iOS (kept as a vector).',
  },
  {
    id: 'text',
    label: 'Text',
    source: { uri: `${BASE}/text.png` },
    note: 'A PNG with text in it, for enableLiveTextInteraction (iOS): long-press the text.',
  },
  {
    id: 'headerOk',
    label: 'Header 200',
    source: { uri: `${BASE}/accept/png`, headers: { Accept: 'image/png' } },
    note: 'source.headers reach the server: /accept/png answers 200 only to Accept: image/png. Headers are not part of the cache key, so this uses noCache.',
    cachePolicy: 'noCache',
  },
  {
    id: 'headerRefused',
    label: 'Header 406',
    source: { uri: `${BASE}/accept/png`, headers: { Accept: 'application/json' } },
    note: "The same URL with Accept: application/json gets 406: onFailure code 'network'. With a caching policy it would be served the PNG cached above, because headers do not key the cache.",
    cachePolicy: 'noCache',
  },
  {
    id: 'missing',
    label: '404',
    source: { uri: `${BASE}/missing/demo.jpg` },
    note: "A 404: onFailure code 'network'.",
  },
  {
    id: 'notAnImage',
    label: 'Not an image',
    source: { uri: `${BASE}/not-an-image/demo` },
    note: "A 200 with an HTML body: onFailure code 'decode'.",
    cachePolicy: 'noCache',
  },
  {
    id: 'notCached',
    label: 'Not cached',
    source: { uri: photoUrl('never-loaded') },
    note: "cacheOnly never touches the network, and nothing loaded this URL: onFailure code 'notCached'.",
    cachePolicy: 'cacheOnly',
  },
  {
    id: 'badScheme',
    label: 'ftp://',
    source: { uri: 'ftp://example.com/demo.png' },
    note: "An unsupported scheme, rejected before any request: onFailure code 'invalidRequest'.",
  },
  {
    id: 'revalidate',
    label: 'ETag',
    source: { uri: `${BASE}/cache/revalidate/demo.jpg` },
    note: 'Served with Cache-Control: no-cache and an ETag. With urlCache, a reload (after Clear memory) revalidates and gets a 304; the other policies ignore HTTP caching headers.',
    cachePolicy: 'urlCache',
  },
];

export function demoSource(id: string): DemoSource {
  return DEMO_SOURCES.find((demo) => demo.id === id) ?? DEMO_SOURCES[0]!;
}

// --- Fixture server --------------------------------------------------------

// Resolves within `timeoutMs`, so a stopped server shows up as "unreachable",
// not as a screen that waits forever.
async function getJson<T>(path: string, timeoutMs = 2000): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${BASE}${path}`, { signal: controller.signal });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return (await response.json()) as T;
  } finally {
    clearTimeout(timer);
  }
}

export async function isServerReachable(): Promise<boolean> {
  try {
    // /__ping answers plain "ok", not JSON; reading it as text is enough.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 2000);
    const response = await fetch(`${BASE}/__ping`, { signal: controller.signal });
    clearTimeout(timer);
    return response.ok && (await response.text()) === 'ok';
  } catch {
    return false;
  }
}

// Requests the server has seen for every path under `prefix`, since it
// started. `aborted` counts responses the client hung up on mid-body: only
// slow bodies are still being written when a cancel arrives, so it is
// meaningful for the `/slow/` datasets only.
export type ServerHits = { count: number; conditional: number; aborted: number };

export function serverHits(prefix: string): Promise<ServerHits> {
  return getJson<ServerHits>(`/__hits?prefix=${encodeURIComponent(prefix)}`);
}
