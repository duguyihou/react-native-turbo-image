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
import { PixelRatio, ScrollView, StyleSheet, Text, View } from 'react-native';
import {
  SafeAreaProvider,
  SafeAreaView,
} from 'react-native-safe-area-context';
import { TurboImage } from 'react-native-turbo-image';
import type { TurboImageProps } from 'react-native-turbo-image';

// Distinct picsum ids so scenarios never share cache entries by accident.
const URI_A = 'https://picsum.photos/id/1025/600/400';
const URI_NEVER_LOADED = 'https://picsum.photos/id/1043/600/400';
const URI_KEYED_1 = 'https://picsum.photos/id/1062/600/400';
const URI_KEYED_2 = 'https://picsum.photos/id/1074/600/400';
const URI_LIFECYCLE = 'https://picsum.photos/id/1084/600/400';
// Large enough (~1 MB) that it is still downloading when JS reacts to
// onStart, so the supersede scenario can cancel it mid-flight.
const URI_LARGE = 'https://picsum.photos/id/1069/3000/2000';
const URI_SMALL = 'https://picsum.photos/id/1080/600/400';
// Used only by the cache-module scenarios (prefetch → dispose chain).
const URI_PREFETCH = 'https://picsum.photos/id/1050/600/400';
// Used only by the processed-variant dispose chain.
const URI_PROCESSED = 'https://picsum.photos/id/1035/600/400';

// `resize` is in points/dp and the core converts it with the screen scale,
// so the processed bitmap is this many pixels wide on either platform.
const RESIZE_DP = 60;
const RESIZED_PX = Math.round(RESIZE_DP * PixelRatio.get());

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
  // Image processors, passed straight through to <TurboImage>.
  processing?: Pick<TurboImageProps, 'resize' | 'blur' | 'monochrome' | 'tint'>;
  expect: Outcome;
  // For expected loads: the exact onSuccess size (in pixels).
  expectSize?: { width: number; height: number };
  // For expected failures: the cross-platform `onFailure.code`.
  expectCode?: string;
  // Mount only after these scenarios have settled.
  after?: string | string[];
  // Scenarios that need more than one load render a probe instead.
  kind?:
    | 'recycle'
    | 'lifecycle'
    | 'supersede'
    | 'prefetch'
    | 'prefetchInvalid'
    | 'dispose'
    | 'clearCaches';
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
    source: { uri: 'https://picsum.photos/id/1036/600/400' },
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
    source: { uri: URI_A.replace('picsum.photos', 'PICSUM.photos') + '#thumb' },
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
  {
    id: 'legacyDataCache',
    title: "1.x cachePolicy 'dataCache' + rounded still work",
    source: { uri: 'https://picsum.photos/id/1011/600/400' },
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
    expectSize: { width: 600, height: 400 },
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
    id: 'liveText',
    title: 'Live Text on an image with text (iOS 16+; no-op on Android)',
    // Asserts the load succeeds with the interaction attached, which
    // exercises the runtime lookup of the Swift class. Whether VisionKit
    // found the text is visible in a screenshot (the Live Text button).
    source: { uri: 'https://dummyimage.com/600x400/ffffff/000000.png&text=TurboImage+Live+Text' },
    enableLiveTextInteraction: true,
    cachePolicy: 'default',
    expect: 'load',
  },
  // httpbin's /image answers according to the Accept header (406 when it
  // cannot), so the outcome proves the header reached the server. noCache
  // because headers deliberately do not key the cache (RFC §4.1).
  {
    id: 'headersSent',
    title: 'source.headers reach the server (Accept: image/png → 200)',
    source: { uri: 'https://httpbin.org/image', headers: { Accept: 'image/png' } },
    cachePolicy: 'noCache',
    expect: 'load',
  },
  {
    id: 'headersChangeResponse',
    title: 'a different header changes the response (Accept: JSON → 406)',
    source: { uri: 'https://httpbin.org/image', headers: [['Accept', 'application/json']] },
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
    source: { uri: 'https://httpbin.org/image', headers: { 'X-Test': 'a\r\nX-Injected: 1' } },
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
    source: { uri: 'https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif' },
    cachePolicy: 'default',
    expect: 'load',
    expectSize: { width: 400, height: 400 },
  },
  {
    id: 'apng',
    title: 'animated PNG (APNG)',
    source: {
      uri: 'https://upload.wikimedia.org/wikipedia/commons/1/14/Animated_PNG_example_bouncing_beach_ball.png',
    },
    cachePolicy: 'default',
    expect: 'load',
    expectSize: { width: 100, height: 100 },
  },
  {
    id: 'webp',
    title: 'animated WebP',
    source: { uri: 'https://www.gstatic.com/webp/animated/1.webp' },
    cachePolicy: 'default',
    expect: 'load',
    expectSize: { width: 300, height: 225 },
  },
  {
    id: 'svg',
    title: 'SVG (size is the view size on Android, the canvas on iOS)',
    source: { uri: 'https://dev.w3.org/SVG/tools/svgweb/samples/svg-files/android.svg' },
    cachePolicy: 'default',
    expect: 'load',
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
    id: 'indicatorEvents',
    title: 'indicator: app handlers still get every event, in order',
    // The spinner is driven by onStart/onCompletion inside <TurboImage>;
    // this checks the app's own handlers are still called around it. That
    // the spinner is drawn was checked by screenshot on a slow load.
    source: { uri: 'https://picsum.photos/id/1015/600/400' },
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
  if (last?.type !== 'completion' || last.state !== 'completed') return 'does not end with completion:completed';
  if (types[types.length - 2] !== 'success') return 'success is not right before completion';
  const progress = events.filter((e): e is Extract<Recorded, { type: 'progress' }> => e.type === 'progress');
  if (progress.length === 0) return 'no progress events for a network load';
  for (let i = 1; i < progress.length; i++) {
    if (progress[i]!.completed < progress[i - 1]!.completed) return 'progress went backwards';
  }
  const final = progress[progress.length - 1]!;
  if (final.total > 0 && final.completed !== final.total) return 'last progress is not completed == total';
  if (types.some((t, i) => t === 'progress' && i > types.indexOf('success'))) return 'progress after success';
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
      else if (all.some((x) => x.type === 'success' && x.source === URI_LARGE)) problem = 'superseded load reported success';
      else problem = validateLoad(all.slice(cancelAt + 1));
      settle(scenario.id, problem === null, 'load', problem ?? describe(all));
    }
  };
  return (
    <TurboImage
      style={styles.image}
      source={{ uri }}
      cachePolicy={scenario.cachePolicy}
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
      onFailure={(e) => settle(scenario.id, false, 'error', `${e.nativeEvent.code}: ${e.nativeEvent.error}`)}
    />
  );
}

function PlainImage({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  return (
    <TurboImage
      testID={`image-${scenario.id}`}
      style={styles.image}
      source={scenario.source}
      placeholder={scenario.placeholder}
      showPlaceholderOnFailure={scenario.showPlaceholderOnFailure}
      rounded={scenario.rounded}
      cachePolicy={scenario.cachePolicy}
      enableLiveTextInteraction={scenario.enableLiveTextInteraction}
      indicator={scenario.indicator}
      {...scenario.processing}
      resizeMode="cover"
      onSuccess={(e) => {
        const { width, height } = e.nativeEvent;
        const sizeOk =
          scenario.expectSize === undefined ||
          (width === scenario.expectSize.width && height === scenario.expectSize.height);
        settle(scenario.id, scenario.expect === 'load' && sizeOk, 'load', `${width}×${height}`);
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
      (ok) => (ok ? setReady(true) : settle(scenario.id, false, 'error', 'module call returned false')),
      (e) => settle(scenario.id, false, 'error', `module call rejected: ${e}`)
    );
    // Run once per mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  if (!ready) {
    return <View style={styles.image} />;
  }
  return <PlainImage scenario={scenario} settle={settle} />;
}

const PrefetchProbe = (p: { scenario: Scenario; settle: Settle }) => (
  <CacheThenView {...p} before={() => TurboImage.prefetch([p.scenario.source])} />
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
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return <View style={styles.image} />;
}

const PROBES = {
  prefetch: PrefetchProbe,
  prefetchInvalid: PrefetchInvalidProbe,
  dispose: DisposeProbe,
  clearCaches: ClearCachesProbe,
  recycle: RecycleProbe,
  lifecycle: LifecycleProbe,
  supersede: SupersedeProbe,
} as const;

function ScenarioCard({ scenario, result, settle }: { scenario: Scenario; result?: Result; settle: Settle }) {
  const Probe = scenario.kind ? PROBES[scenario.kind] : PlainImage;
  const status = result ? `${result.ok ? 'PASS' : 'FAIL'} · ${result.outcome}: ${result.detail}` : 'running…';
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
    report(`TURBOIMAGE_SMOKE ${JSON.stringify({ pass, passed, total: SCENARIOS.length, blocked, failed })}`);
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
              ? { ok: false, outcome: 'blocked', detail: `never ran; waiting for ${waitingFor.join(', ')}` }
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
            <ScenarioCard key={scenario.id} scenario={scenario} result={results[scenario.id]} settle={settle} />
          ))}
        </ScrollView>
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 16 },
  title: { fontSize: 20, fontWeight: '600' },
  summary: { fontSize: 15, fontFamily: 'Menlo' },
  card: { gap: 8 },
  label: { fontSize: 12, fontFamily: 'Menlo' },
  image: { width: '100%', aspectRatio: 3 / 2, backgroundColor: '#ddd' },
});
