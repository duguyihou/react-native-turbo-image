// TurboImage 2.0 example and on-device smoke test.
//
// Each scenario checks one cross-platform contract through the real Fabric
// view and the real Nuke/Coil adapter: cache keys, the cache-policy tier
// matrix, validation, error codes, placeholders, view recycling, and the
// event lifecycle. Scenarios that depend on cache state mount strictly after
// the load they depend on, so outcomes are deterministic.
//
// When every scenario has settled, the app logs exactly one line:
//   TURBOIMAGE_SMOKE {"pass":true,"results":{...}}
// scripts/smoke-{android,ios}.sh wait for that line in release builds.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
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
  expect: Outcome;
  // For expected failures: the cross-platform `onFailure.code`.
  expectCode?: string;
  // Mount only after this scenario has settled.
  after?: string;
  // Scenarios that need more than one load render a probe instead.
  kind?: 'recycle' | 'lifecycle' | 'supersede';
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
      {...recorder(scenario.source.uri, push)}
    />
  );
}

function SupersedeProbe({ scenario, settle }: { scenario: Scenario; settle: Settle }) {
  const [uri, setUri] = useState(scenario.source.uri);
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
      resizeMode="cover"
      onSuccess={(e) =>
        settle(scenario.id, scenario.expect === 'load', 'load', `${e.nativeEvent.width}×${e.nativeEvent.height}`)
      }
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

const PROBES = {
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

  const mounted = useMemo(() => SCENARIOS.filter((s) => !s.after || results[s.after]), [results]);
  const settled = Object.keys(results).length === SCENARIOS.length;

  useEffect(() => {
    if (!settled || reported.current) {
      return;
    }
    reported.current = true;
    const pass = Object.values(results).every((r) => r.ok);
    // Release builds on iOS drop everything below RCTLogLevelError, and the
    // smoke scripts run release builds, so the result has to go out as an
    // error there. Debug keeps console.log to avoid a LogBox error toast.
    const report = __DEV__ ? console.log : console.error;
    report(`TURBOIMAGE_SMOKE ${JSON.stringify({ pass, results })}`);
  }, [settled, results]);

  useEffect(() => {
    const timer = setTimeout(() => {
      setResults((prev) => {
        const next = { ...prev };
        for (const s of SCENARIOS) {
          next[s.id] ??= { ok: false, outcome: 'timeout', detail: '' };
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
