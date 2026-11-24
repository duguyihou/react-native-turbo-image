// Benchmark app: the same scenarios with TurboImage, expo-image or RN's
// <Image>, one library per launch so they don't compete for resources.
//
// scripts/bench-android.sh launches it with a deep link, e.g.
// turboimagebench://run?lib=expo&scenario=grid&source=photo, and reads the
// result line:
//   TURBOIMAGE_BENCH {"lib":"expo","scenario":"grid",...}
// Without a link the app shows a menu. Images come from the local
// scripts/fixture-server.py, so the network is the same every run.
import { FlashList } from '@shopify/flash-list';
import type { FlashListRef } from '@shopify/flash-list';
import { useEffect, useRef, useState } from 'react';
import { Dimensions, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { LIBRARIES, isLibraryName } from './adapters';
import type { LibraryName } from './adapters';

// RN has `performance.now()` at runtime, but its types don't declare it.
declare const performance: { now(): number };

// Must match fixture_server_port in scripts/fixture-server.sh.
const BASE = 'http://localhost:8765';

// `photo`: 600×400, a feed thumbnail. `large`: 3000×2000, where decoding at
// view size matters most.
type SourceName = 'photo' | 'large';

// One URL per image (no accidental cache hits), stable across launches (so
// a second launch measures a warm disk cache).
const imageUrl = (source: SourceName, scenario: string, index: number) =>
  `${BASE}/${source}/${scenario}-${index}.jpg`;

const COLUMNS = 3;
const CELL = Math.floor(Dimensions.get('window').width / COLUMNS);

// `count` is the number of images in `load` (deep link `n`, default 30).
type Run = { lib: LibraryName; scenario: ScenarioName; source: SourceName; count: number };
type ScenarioName = 'load' | 'grid';

// --- Results -------------------------------------------------------------

// Collects the time from mount to each image's success event.
function useLoadTimes() {
  // Set by the first effect, once the views are committed.
  const mountedAt = useRef(0);
  useEffect(() => {
    mountedAt.current = performance.now();
  }, []);
  const times = useRef<number[]>([]);
  // Each load's start event, to split pre-request time from fetch+decode.
  const starts = useRef<number[]>([]);
  const failures = useRef<string[]>([]);
  return {
    onStart: () => starts.current.push(performance.now() - mountedAt.current),
    onLoad: () => times.current.push(performance.now() - mountedAt.current),
    onError: (message: string) => failures.current.push(message),
    settled: () => times.current.length + failures.current.length,
    summary: () => {
      // Not `toSorted`: RN's TS preset lacks es2023.array.
      // oxlint-disable-next-line unicorn/no-array-sort
      const sorted = [...times.current].sort((a, b) => a - b);
      const at = (q: number) =>
        sorted.length === 0
          ? null
          : Math.round(sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))]);
      return {
        loaded: sorted.length,
        failed: failures.current.length,
        firstError: failures.current[0] ?? null,
        firstMs: at(0),
        p50Ms: at(0.5),
        p90Ms: at(0.9),
        lastMs: at(1),
        // Start events arrive in order: first and last.
        startFirstMs: starts.current.length ? Math.round(starts.current[0]) : null,
        startLastMs: starts.current.length ? Math.round(starts.current.at(-1)!) : null,
      };
    },
  };
}

function report(run: Run, result: object) {
  console.log(`TURBOIMAGE_BENCH ${JSON.stringify({ ...run, ...result })}`);
}

// --- Scenario: load ------------------------------------------------------
//
// Time to load 30 images that mount at once (no virtualization). Ends when
// all have settled, or after 30 s.

const LOAD_TIMEOUT_MS = 30_000;

function LoadScenario({ run }: { run: Run }) {
  const Image = LIBRARIES[run.lib];
  const times = useLoadTimes();
  const done = useRef(false);

  const finish = (timedOut: boolean) => {
    if (done.current) return;
    done.current = true;
    report(run, { n: run.count, timedOut, ...times.summary() });
  };

  useEffect(() => {
    const timer = setTimeout(() => finish(true), LOAD_TIMEOUT_MS);
    return () => clearTimeout(timer);
    // Runs once: `finish` only reads refs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const settle = () => {
    if (times.settled() === run.count) finish(false);
  };

  return (
    <View style={styles.wrap}>
      {Array.from({ length: run.count }, (_, i) => (
        <Image
          key={i}
          uri={imageUrl(run.source, 'load', i)}
          size={CELL}
          recyclingKey={String(i)}
          onStart={times.onStart}
          onLoad={() => {
            times.onLoad();
            settle();
          }}
          onError={(message) => {
            times.onError(message);
            settle();
          }}
        />
      ))}
    </View>
  );
}

// --- Scenario: grid ------------------------------------------------------
//
// Scrolling a long FlashList grid: tests recycling, cancellation and
// eviction. The app scrolls itself a screen at a time on a timer, so every
// library sees the same scroll. The script reads `dumpsys gfxinfo` between:
//   TURBOIMAGE_BENCH_READY  the first screen has loaded; scrolling starts
//                           SCROLL_DELAY_MS later (the script resets the
//                           frame stats in that gap)
//   TURBOIMAGE_BENCH {...}  scrolling has finished
//
// TODO: a fling-speed run with real touches (Maestro/Flashlight), to stress
// cancellation harder.

const GRID_COUNT = 900;
const SCROLL_DELAY_MS = 2_000;
const SCROLL_STEP_MS = 300;

function GridScenario({ run }: { run: Run }) {
  const Image = LIBRARIES[run.lib];
  const times = useLoadTimes();
  const list = useRef<FlashListRef<number>>(null);
  const [started, setStarted] = useState(false);
  const data = useRef(Array.from({ length: GRID_COUNT }, (_, i) => i)).current;

  // Ready once the first screen settles, or after 10 s so failures don't hang.
  const firstScreen = COLUMNS * Math.ceil(Dimensions.get('window').height / CELL);
  useEffect(() => {
    if (started) return;
    const poll = setInterval(() => {
      if (times.settled() >= firstScreen) setStarted(true);
    }, 50);
    const fallback = setTimeout(() => setStarted(true), 10_000);
    return () => {
      clearInterval(poll);
      clearTimeout(fallback);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [started]);

  useEffect(() => {
    if (!started) return;
    console.log('TURBOIMAGE_BENCH_READY');
    const height = Dimensions.get('window').height;
    const end = Math.ceil(GRID_COUNT / COLUMNS) * CELL - height;
    let offset = 0;
    let step: ReturnType<typeof setInterval> | undefined;
    const delay = setTimeout(() => {
      const scrollStartedAt = performance.now();
      step = setInterval(() => {
        offset = Math.min(end, offset + height);
        list.current?.scrollToOffset({ offset, animated: true });
        if (offset >= end) {
          clearInterval(step);
          // Let the last scroll and its loads finish first.
          setTimeout(() => {
            report(run, {
              n: GRID_COUNT,
              scrollMs: Math.round(performance.now() - scrollStartedAt),
              ...times.summary(),
            });
          }, 1_000);
        }
      }, SCROLL_STEP_MS);
    }, SCROLL_DELAY_MS);
    return () => {
      clearTimeout(delay);
      clearInterval(step);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [started]);

  return (
    <FlashList
      ref={list}
      data={data}
      numColumns={COLUMNS}
      keyExtractor={(i) => String(i)}
      renderItem={({ item }) => (
        <Image
          uri={imageUrl(run.source, 'grid', item)}
          size={CELL}
          recyclingKey={String(item)}
          onStart={times.onStart}
          onLoad={times.onLoad}
          onError={times.onError}
        />
      )}
    />
  );
}

// --- Launching -----------------------------------------------------------

// Parsed by hand to avoid relying on the runtime's URL implementation.
function parseRun(url: string | null): Run | null {
  if (url === null) return null;
  const param = (key: string) => url.match(new RegExp(`[?&]${key}=([^&]+)`))?.[1] ?? null;
  const lib = param('lib');
  const scenario = param('scenario');
  const source = param('source') ?? 'photo';
  const count = Number(param('n') ?? 30);
  if (!isLibraryName(lib)) return null;
  if (scenario !== 'load' && scenario !== 'grid') return null;
  if (source !== 'photo' && source !== 'large') return null;
  if (!Number.isInteger(count) || count < 1) return null;
  return { lib, scenario, source, count };
}

export default function App() {
  // `undefined` while the initial URL is being read; `null` for no run.
  const [run, setRun] = useState<Run | null | undefined>(undefined);

  useEffect(() => {
    Linking.getInitialURL().then((url) => setRun(parseRun(url ?? null)));
  }, []);

  if (run === undefined) return <View style={styles.screen} />;
  if (run === null) return <Menu onPick={setRun} />;
  return (
    <View style={styles.screen}>
      {run.scenario === 'load' ? <LoadScenario run={run} /> : <GridScenario run={run} />}
    </View>
  );
}

// For running by hand (e.g. under a profiler); results still go to the log.
function Menu({ onPick }: { onPick: (run: Run) => void }) {
  const runs: Run[] = [];
  for (const lib of Object.keys(LIBRARIES) as LibraryName[]) {
    for (const scenario of ['load', 'grid'] as const) {
      for (const source of ['photo', 'large'] as const)
        runs.push({ lib, scenario, source, count: 30 });
    }
  }
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.menu}>
      {runs.map((r) => (
        <Pressable
          key={`${r.lib}-${r.scenario}-${r.source}`}
          onPress={() => onPick(r)}
          style={styles.item}
        >
          <Text style={styles.itemText}>{`${r.lib} · ${r.scenario} · ${r.source}`}</Text>
        </Pressable>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#fff' },
  wrap: { flexDirection: 'row', flexWrap: 'wrap' },
  menu: { padding: 16, paddingTop: 64 },
  item: { paddingVertical: 12, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: '#ccc' },
  itemText: { fontSize: 16 },
});
