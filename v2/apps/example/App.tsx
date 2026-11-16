// TurboImage 2.0 example and on-device smoke test.
//
// Each scenario checks one cross-platform contract owned by the C++ core
// (cache keys, the cache-policy tier matrix, validation) through the real
// Fabric view and the real Nuke/Coil adapter. Scenarios that depend on cache
// state run strictly after the load they depend on, so the outcome is
// deterministic.
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

type Outcome = 'load' | 'error';

type Scenario = {
  id: string;
  title: string;
  source: TurboImageProps['source'];
  cachePolicy: NonNullable<TurboImageProps['cachePolicy']>;
  // Failing scenarios carry a placeholder: it must stay visible after the
  // failure, on both platforms (check screenshots side by side).
  placeholder?: TurboImageProps['placeholder'];
  expect: Outcome;
  // For expected errors: the cross-platform `onError.code` that must match.
  expectCode?: string;
  // Mount only after this scenario has settled.
  after?: string;
  // Scenarios that need more than one <TurboImage> render this instead.
  kind?: 'recycle';
};

const SCENARIOS: Scenario[] = [
  // The two placeholder scenarios come first so screenshots show them.
  {
    id: 'unsupportedScheme',
    title: 'core rejects unsupported schemes',
    source: { uri: 'ftp://example.com/a.png' },
    placeholder: { thumbhash: '4AcKPJpwd3dwd3eHh3eAgAj3iA==' },
    cachePolicy: 'default',
    expect: 'error',
    expectCode: 'invalidRequest',
  },
  {
    id: 'cacheMiss',
    title: 'cacheOnly never touches the network',
    source: { uri: URI_NEVER_LOADED },
    placeholder: { blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj' },
    cachePolicy: 'cacheOnly',
    expect: 'error',
    expectCode: 'notCached',
    after: 'network',
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
    // Same image with a fragment and an upper-case host: the core's
    // canonical key must map it to the entry `network` wrote.
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
    // Mounts an image, unmounts it once loaded, then mounts a new one with
    // the same source. Fabric on iOS hands back the recycled view, whose
    // stale props used to suppress the reload (blank image forever).
    source: { uri: URI_A },
    cachePolicy: 'default',
    expect: 'load',
    after: 'network',
    kind: 'recycle',
  },
];

// Fail rather than hang if a callback never arrives (e.g. a lost event).
const TIMEOUT_MS = 30_000;

type Result = { outcome: Outcome | 'timeout'; detail: string; ok: boolean };

// First mount loads, unmounts, and a second <TurboImage> with the same
// source takes its place; only the second mount settles the scenario.
function RecycleProbe({
  scenario,
  onSettled,
}: {
  scenario: Scenario;
  onSettled: (id: string, outcome: Outcome, detail: string, code?: string) => void;
}) {
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
      testID={`image-${scenario.id}-${phase}`}
      style={styles.image}
      source={scenario.source}
      cachePolicy={scenario.cachePolicy}
      onLoad={(e) =>
        phase === 'first'
          ? setPhase('gap')
          : onSettled(scenario.id, 'load', `${e.nativeEvent.width}×${e.nativeEvent.height}`)
      }
      onError={(e) =>
        onSettled(scenario.id, 'error', `${e.nativeEvent.code}: ${e.nativeEvent.message}`, e.nativeEvent.code)
      }
    />
  );
}

function ScenarioCard({
  scenario,
  result,
  onSettled,
}: {
  scenario: Scenario;
  result?: Result;
  onSettled: (
    id: string,
    outcome: Outcome,
    detail: string,
    code?: string
  ) => void;
}) {
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
      {scenario.kind === 'recycle' ? (
        <RecycleProbe scenario={scenario} onSettled={onSettled} />
      ) : (
      <TurboImage
        testID={`image-${scenario.id}`}
        style={styles.image}
        source={scenario.source}
        placeholder={scenario.placeholder}
        cachePolicy={scenario.cachePolicy}
        resizeMode="cover"
        onLoad={(e) =>
          onSettled(
            scenario.id,
            'load',
            `${e.nativeEvent.width}×${e.nativeEvent.height}`
          )
        }
        onError={(e) =>
          onSettled(
            scenario.id,
            'error',
            `${e.nativeEvent.code}: ${e.nativeEvent.message}`,
            e.nativeEvent.code
          )
        }
      />
      )}
    </View>
  );
}

export default function App() {
  const [results, setResults] = useState<Record<string, Result>>({});
  const reported = useRef(false);

  // First callback wins: a duplicate onLoad (e.g. a restarted Coil request
  // after reattach) must not flip a settled result.
  const onSettled = useCallback(
    (id: string, outcome: Outcome, detail: string, code?: string) => {
      setResults((prev) => {
        if (prev[id]) {
          return prev;
        }
        const scenario = SCENARIOS.find((s) => s.id === id)!;
        return {
          ...prev,
          [id]: {
            outcome,
            detail,
            ok:
              outcome === scenario.expect &&
              (scenario.expectCode === undefined ||
                code === scenario.expectCode),
          },
        };
      });
    },
    []
  );

  const mounted = useMemo(
    () => SCENARIOS.filter((s) => !s.after || results[s.after]),
    [results]
  );
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
          next[s.id] ??= { outcome: 'timeout', detail: '', ok: false };
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
              onSettled={onSettled}
            />
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
