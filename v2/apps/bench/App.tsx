// TurboImage benchmark app: the same scenarios rendered with TurboImage,
// expo-image or React Native's <Image>, one library per launch.
//
// One library per process, because libraries running side by side would
// share memory pressure, network connections and decode threads, and each
// would slow the others in ways that have nothing to do with it.
//
// scripts/bench-android.sh launches the app with a deep link that names the
// run, e.g. turboimagebench://run?lib=expo&scenario=grid&source=photo, and
// reads the single result line the scenario logs:
//   TURBOIMAGE_BENCH {"lib":"expo","scenario":"grid",...}
// Launched by hand, without a link, the app shows a menu instead.
//
// Images come from scripts/fixture-server.py on the host (adb reverse on
// Android), so the network is a local, fixed one: differences between runs
// are the libraries', not a CDN's.
import { FlashList } from '@shopify/flash-list';
import type { FlashListRef } from '@shopify/flash-list';
import { useEffect, useRef, useState } from 'react';
import { Dimensions, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { LIBRARIES, isLibraryName } from './adapters';
import type { LibraryName } from './adapters';

// React Native provides `performance.now()` (a monotonic clock with
// sub-millisecond resolution) at runtime, but its TypeScript types don't
// declare it, and the app's tsconfig has no DOM lib that would.
declare const performance: { now(): number };

// Must match fixture_server_port in scripts/fixture-server.sh.
const BASE = 'http://localhost:8765';

// `photo` is a 600×400 JPEG, roughly what a feed serves for a thumbnail.
// `large` is 3000×2000, a camera photo shown as a thumbnail: the case where
// decoding at the view's size instead of the full size matters most.
type SourceName = 'photo' | 'large';

// Every image has a URL of its own, so nothing is a cache hit by accident.
// The URLs are the same on every launch, which is what lets a second launch
// without clearing app data measure a warm disk cache.
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
  // Set by the first effect, i.e. when the scenario's views have been
  // committed: the moment their image requests can start.
  const mountedAt = useRef(0);
  useEffect(() => {
    mountedAt.current = performance.now();
  }, []);
  const times = useRef<number[]>([]);
  // When each library reports that a load began. Separates time spent
  // before the request is issued (props reaching native, waiting for
  // layout) from time spent fetching and decoding.
  const starts = useRef<number[]>([]);
  const failures = useRef<string[]>([]);
  return {
    onStart: () => starts.current.push(performance.now() - mountedAt.current),
    onLoad: () => times.current.push(performance.now() - mountedAt.current),
    onError: (message: string) => failures.current.push(message),
    settled: () => times.current.length + failures.current.length,
    summary: () => {
      // Sorts a copy. Not `toSorted`: RN's TypeScript preset leaves
      // es2023.array out of its lib list.
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
        // Start events arrive in the order loads began, so these are the
        // earliest and latest.
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
// Time to load a screenful of images that all mount at once: 30 cells, no
// list virtualization, so every request starts together. Measures request
// scheduling, download, decode and hand-off to the view. Ends when every
// image has succeeded or failed, or after 30 s.

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
// Scrolling a long FlashList grid, the case where libraries differ most in
// dropped frames and memory: views are recycled, requests for rows that
// scrolled away must be cancelled, and decoded images must be evicted.
//
// The app scrolls itself, a screen at a time on a fixed timer, so every
// library sees exactly the same scroll. The bench script measures frames
// with `dumpsys gfxinfo` between two log lines:
//   TURBOIMAGE_BENCH_READY  the first screen has loaded; scrolling starts
//                           SCROLL_DELAY_MS later (the script resets the
//                           frame stats in that gap)
//   TURBOIMAGE_BENCH {...}  scrolling has finished
//
// TODO: also a fling-speed run driven by real touches (Maestro/Flashlight),
// which exercises the libraries' cancellation harder than a paged scroll.

const GRID_COUNT = 900;
const SCROLL_DELAY_MS = 2_000;
const SCROLL_STEP_MS = 300;

function GridScenario({ run }: { run: Run }) {
  const Image = LIBRARIES[run.lib];
  const times = useLoadTimes();
  const list = useRef<FlashListRef<number>>(null);
  const [started, setStarted] = useState(false);
  const data = useRef(Array.from({ length: GRID_COUNT }, (_, i) => i)).current;

  // Ready once the first screen has settled (or after 10 s, so a library
  // that fails every load still produces a result rather than hanging).
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
          // Lets the last animation and its loads finish before the script
          // reads the frame stats.
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

// Parsed by hand: only three known keys, and no dependency on how complete
// the runtime's URL implementation is.
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

// For running a scenario by hand, e.g. under a profiler. Results still go
// to the log.
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
