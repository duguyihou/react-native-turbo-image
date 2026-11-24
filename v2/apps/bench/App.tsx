// Benchmark app: the same scenarios with TurboImage, expo-image or RN's
// <Image>, one library per launch so they don't compete for resources.
//
// scripts/bench-{android,ios}.sh launch it with a deep link, e.g.
//   turboimagebench://run?lib=expo&scenario=grid&source=photo&n=900&speed=fast
// (on iOS as the `-launchURL` launch argument, which needs no confirmation)
// and read its log lines:
//   TURBOIMAGE_BENCH_READY      the measured phase starts; the script resets
//                               frame stats here
//   TURBOIMAGE_BENCH_OFFLINE    (offline) every image has failed; the script
//                               starts the server again
//   TURBOIMAGE_BENCH {...}      the result
// Without a link the app shows a menu, for runs under a profiler.
//
// The app measures only what JS can see truthfully: when each image's
// "load started" and "loaded" events arrive. Request counts, memory and
// frame statistics come from outside the app (the fixture server, `dumpsys`,
// `footprint`), taken by the scripts. See docs/benchmark/BENCHMARK_METHODOLOGY.md.
import { FlashList } from '@shopify/flash-list';
import type { FlashListRef } from '@shopify/flash-list';
import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import {
  Dimensions,
  Linking,
  Platform,
  Pressable,
  ScrollView,
  Settings,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { LIBRARIES, isLibraryName } from './adapters';
import type { LibraryName } from './adapters';

// RN has `performance.now()` at runtime, but its types don't declare it.
declare const performance: { now(): number };

// Must match fixture_server_port in scripts/fixture-server.sh.
const BASE = 'http://localhost:8765';

// --- Datasets ------------------------------------------------------------
//
// `photo`: 600×400 JPEG (28 KB), a feed thumbnail. `large`: 3000×2000 JPEG
// (368 KB), where decoding at the view's size matters. `slow`: the large
// JPEG sent over about 2 s (the fixture server's /slow/), so loads are still
// downloading when they are cancelled.
type SourceName = 'photo' | 'large' | 'slow';
const SOURCE_PATH: Record<SourceName, string> = {
  photo: 'photo',
  large: 'large',
  slow: 'slow/large',
};

// `unique`: one URL per image, stable across launches (so a second launch
// measures a warm disk cache). `repeated`: 12 URLs over all the images, as
// in a list of avatars.
type UrlsName = 'unique' | 'repeated';
const REPEATED_URLS = 12;

function imageUrl(run: Run, index: number) {
  const name = run.urls === 'repeated' ? `r${index % REPEATED_URLS}` : String(index);
  return `${BASE}/${SOURCE_PATH[run.source]}/${run.scenario}-${name}.jpg`;
}

const COLUMNS = 3;
const CELL = Math.floor(Dimensions.get('window').width / COLUMNS);
const SCREEN_HEIGHT = Dimensions.get('window').height;
// Cells in one screenful: what the user sees at once.
const FIRST_SCREEN = COLUMNS * Math.ceil(SCREEN_HEIGHT / CELL);

type ScenarioName = 'load' | 'grid' | 'remount' | 'cancel' | 'offline';
type Run = {
  lib: LibraryName;
  scenario: ScenarioName;
  source: SourceName;
  urls: UrlsName;
  // Images in `load` and `grid` (deep link `n`).
  count: number;
  // `grid` only. `paced`: one screen per 300 ms, animated, as a user
  // flicking. `fast`: one screen per frame, not animated, a fling that
  // outruns every loader.
  speed: 'paced' | 'fast';
};

// Fail rather than hang when an image never settles.
const SCENARIO_TIMEOUT_MS = 60_000;

// --- Measurements --------------------------------------------------------

// Per image: when its first "load started" and first "loaded" (or failed)
// events arrived, by index. Indices, not URLs, so repeated URLs still count
// as separate images.
function useLoadTimes() {
  // Set by the first effect, once the views are committed (as before this
  // file measured more than `load`), or by `restart`.
  const mountedAt = useRef(0);
  useEffect(() => {
    if (mountedAt.current === 0) mountedAt.current = performance.now();
  }, []);
  const startAt = useRef(new Map<number, number>());
  const loadAt = useRef(new Map<number, number>());
  const failures = useRef(new Map<number, string>());
  const events = useRef({ starts: 0, loads: 0, errors: 0 });

  return {
    // Resets the clock and the per-image times (a new mount of the same list).
    restart: () => {
      mountedAt.current = performance.now();
      startAt.current.clear();
      loadAt.current.clear();
      failures.current.clear();
    },
    onStart: (index: number) => {
      events.current.starts++;
      if (!startAt.current.has(index)) startAt.current.set(index, performance.now());
    },
    onLoad: (index: number) => {
      events.current.loads++;
      if (!loadAt.current.has(index)) loadAt.current.set(index, performance.now());
    },
    onError: (index: number, message: string) => {
      events.current.errors++;
      if (!failures.current.has(index)) failures.current.set(index, message);
    },
    settled: (indices?: number[]) =>
      indices === undefined
        ? loadAt.current.size + failures.current.size
        : indices.filter((i) => loadAt.current.has(i) || failures.current.has(i)).length,
    loadedAt: (index: number) => loadAt.current.get(index),
    summary: () => {
      const sinceMount = [...loadAt.current.values()].map((t) => t - mountedAt.current);
      // Only images whose library reported a start (expo-image's onLoadStart
      // and TurboImage's onStart both fire per load, but a library may skip
      // it for a memory hit; `withStart` says how many had one).
      const latencies: number[] = [];
      for (const [index, loaded] of loadAt.current) {
        const started = startAt.current.get(index);
        if (started !== undefined) latencies.push(loaded - started);
      }
      return {
        loaded: loadAt.current.size,
        failed: failures.current.size,
        firstError: failures.current.values().next().value ?? null,
        events: { ...events.current },
        withStart: latencies.length,
        // Mount → loaded: what a user waits for (load and remount).
        firstMs: quantile(sinceMount, 0),
        p50Ms: quantile(sinceMount, 0.5),
        p95Ms: quantile(sinceMount, 0.95),
        lastMs: quantile(sinceMount, 1),
        // Start event → loaded: the library's own pipeline per image.
        latencyP50Ms: quantile(latencies, 0.5),
        latencyP95Ms: quantile(latencies, 0.95),
      };
    },
  };
}
type LoadTimes = ReturnType<typeof useLoadTimes>;

// Nearest-rank quantile, rounded to whole ms; null when empty.
function quantile(values: number[], q: number): number | null {
  if (values.length === 0) return null;
  // Not `toSorted`: RN's TS preset lacks es2023.array.
  // oxlint-disable-next-line unicorn/no-array-sort
  const sorted = [...values].sort((a, b) => a - b);
  return Math.round(
    sorted[Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1)] ?? sorted[0]!
  );
}

// iOS release builds drop logs below error level; the script reads both.
const log = (line: string) => (__DEV__ ? console.log : console.error)(line);

function report(run: Run, result: object) {
  log(`TURBOIMAGE_BENCH ${JSON.stringify({ ...run, platform: Platform.OS, ...result })}`);
}

// Resolves once `ready()` is true (polled every 50 ms), or after `timeoutMs`.
function waitFor(ready: () => boolean, timeoutMs: number): Promise<boolean> {
  return new Promise((resolve) => {
    const startedAt = performance.now();
    const poll = setInterval(() => {
      const ok = ready();
      if (ok || performance.now() - startedAt > timeoutMs) {
        clearInterval(poll);
        resolve(ok);
      }
    }, 50);
  });
}

const indicesFrom = (first: number, count: number) =>
  Array.from({ length: count }, (_, i) => first + i);

// One cell of every scenario: the library's image with handlers by index.
function Cell({ run, index, times }: { run: Run; index: number; times: LoadTimes }) {
  const Image = LIBRARIES[run.lib];
  return (
    <Image
      uri={imageUrl(run, index)}
      size={CELL}
      recyclingKey={String(index)}
      onStart={() => times.onStart(index)}
      onLoad={() => times.onLoad(index)}
      onError={(message) => times.onError(index, message)}
    />
  );
}

// --- Scenario: load ------------------------------------------------------
//
// `n` images mounted at once, without virtualization. Ends when all have
// settled. Measures time to first image, to the last, and the spread.

function LoadScenario({ run }: { run: Run }) {
  const times = useLoadTimes();
  useEffect(() => {
    log('TURBOIMAGE_BENCH_READY');
    waitFor(() => times.settled() === run.count, SCENARIO_TIMEOUT_MS).then((ok) =>
      report(run, { timedOut: !ok, ...times.summary() })
    );
    // Once per launch: `times` only holds refs.
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);
  return (
    <View style={styles.wrap}>
      {indicesFrom(0, run.count).map((i) => (
        <Cell key={i} run={run} index={i} times={times} />
      ))}
    </View>
  );
}

// --- Scenario: grid ------------------------------------------------------
//
// A FlashList grid of `n` images scrolled from top to bottom by the app
// itself, so every library sees the same scroll. Measures:
//   - firstScreenMs: mount → the first screen has settled (before scrolling);
//   - lastScreenMs: scroll end → the last screen has settled. A loader that
//     keeps downloading cells already scrolled past makes this long;
//   - scrollMs: how long the scripted scroll took (JS thread).
// Frame statistics (Android `dumpsys gfxinfo`) cover READY → result.

const PACED_STEP_MS = 300;

function GridScenario({ run }: { run: Run }) {
  const times = useLoadTimes();
  const list = useRef<FlashListRef<number>>(null);
  const data = useRef(indicesFrom(0, run.count)).current;

  useEffect(() => {
    let cancelled = false;
    let frame = 0;
    let step: ReturnType<typeof setInterval> | undefined;
    const rows = Math.ceil(run.count / COLUMNS);
    const end = Math.max(0, rows * CELL - SCREEN_HEIGHT);
    const lastScreen = indicesFrom(
      Math.max(0, run.count - FIRST_SCREEN - COLUMNS),
      Math.min(run.count, FIRST_SCREEN + COLUMNS)
    );

    const afterScroll = (scrollStartedAt: number, firstScreenMs: number | null) => {
      const scrollEndedAt = performance.now();
      waitFor(() => times.settled(lastScreen) === lastScreen.length, SCENARIO_TIMEOUT_MS).then(
        (ok) => {
          if (cancelled) return;
          // The last of the last screen's images, measured from scroll end.
          const lastLoad = Math.max(...lastScreen.map((i) => times.loadedAt(i) ?? 0));
          report(run, {
            timedOut: !ok,
            firstScreenMs,
            scrollMs: Math.round(scrollEndedAt - scrollStartedAt),
            lastScreenMs: lastLoad > 0 ? Math.round(lastLoad - scrollEndedAt) : null,
            ...times.summary(),
          });
        }
      );
    };

    const firstScreen = indicesFrom(0, Math.min(FIRST_SCREEN, run.count));
    waitFor(() => times.settled(firstScreen) === firstScreen.length, 10_000).then(() => {
      if (cancelled) return;
      const firstScreenMs = times.summary().lastMs;
      log('TURBOIMAGE_BENCH_READY');
      // A pause, so the script's frame-stats reset lands before scrolling.
      setTimeout(() => {
        if (cancelled) return;
        const scrollStartedAt = performance.now();
        let offset = 0;
        if (run.speed === 'fast') {
          const tick = () => {
            offset = Math.min(end, offset + SCREEN_HEIGHT);
            list.current?.scrollToOffset({ offset, animated: false });
            if (offset >= end) afterScroll(scrollStartedAt, firstScreenMs);
            else frame = requestAnimationFrame(tick);
          };
          frame = requestAnimationFrame(tick);
        } else {
          step = setInterval(() => {
            offset = Math.min(end, offset + SCREEN_HEIGHT);
            list.current?.scrollToOffset({ offset, animated: true });
            if (offset >= end) {
              clearInterval(step);
              afterScroll(scrollStartedAt, firstScreenMs);
            }
          }, PACED_STEP_MS);
        }
      }, 2_000);
    });
    return () => {
      cancelled = true;
      cancelAnimationFrame(frame);
      clearInterval(step);
    };
    // Once per launch.
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);

  return (
    <FlashList
      ref={list}
      data={data}
      numColumns={COLUMNS}
      keyExtractor={(i) => String(i)}
      renderItem={({ item }) => <Cell run={run} index={item} times={times} />}
    />
  );
}

// --- Scenario: remount ---------------------------------------------------
//
// One screen of images mounted for 250 ms and unmounted for one frame, 20
// times, as a user opening and leaving a screen. Then mounted for good.
// Measures how long that final mount takes to settle: work left over from
// the unmounted views (decodes, downloads nobody wants) delays it.

const REMOUNT_CYCLES = 20;
const REMOUNT_MOUNTED_MS = 250;

function RemountScenario({ run }: { run: Run }) {
  // Events from the 20 discarded mounts go to their own recorder, so a late
  // one can never count for the final mount.
  const discarded = useLoadTimes();
  const times = useLoadTimes();
  const [cycle, setCycle] = useState(0);
  const [mounted, setMounted] = useState(true);
  const count = Math.min(FIRST_SCREEN, run.count);

  useEffect(() => {
    if (cycle === 0) log('TURBOIMAGE_BENCH_READY');
    if (cycle < REMOUNT_CYCLES) {
      let frame = 0;
      const timer = setTimeout(() => {
        setMounted(false);
        frame = requestAnimationFrame(() => {
          // Before the final mount renders, so its fastest loads count.
          if (cycle + 1 === REMOUNT_CYCLES) times.restart();
          setCycle((c) => c + 1);
          setMounted(true);
        });
      }, REMOUNT_MOUNTED_MS);
      return () => {
        clearTimeout(timer);
        cancelAnimationFrame(frame);
      };
    }
    // The final mount: only its own loads count.
    waitFor(() => times.settled() === count, SCENARIO_TIMEOUT_MS).then((ok) =>
      report(run, { timedOut: !ok, cycles: REMOUNT_CYCLES, count, ...times.summary() })
    );
    return undefined;
    // Per cycle.
    // oxlint-disable-next-line react/exhaustive-deps
  }, [cycle]);

  if (!mounted) return <View style={styles.screen} />;
  return (
    <View key={cycle} style={styles.wrap}>
      {indicesFrom(0, count).map((i) => (
        <Cell key={i} run={run} index={i} times={cycle < REMOUNT_CYCLES ? discarded : times} />
      ))}
    </View>
  );
}

// --- Scenario: cancel ----------------------------------------------------
//
// A screen of slow images (about 2 s each) starts loading; 300 ms later the
// list jumps to its end and stays. The first screen's downloads are now
// unwanted. Measures how long the destination screen takes (`lastScreenMs`);
// the script reads from the server how many bodies the client abandoned.

function CancelScenario({ run }: { run: Run }) {
  const times = useLoadTimes();
  const list = useRef<FlashListRef<number>>(null);
  const count = Math.max(run.count, FIRST_SCREEN * 10);
  const data = useRef(indicesFrom(0, count)).current;

  useEffect(() => {
    let cancelled = false;
    log('TURBOIMAGE_BENCH_READY');
    const rows = Math.ceil(count / COLUMNS);
    const lastScreen = indicesFrom(count - FIRST_SCREEN, FIRST_SCREEN);
    const timer = setTimeout(() => {
      list.current?.scrollToOffset({ offset: rows * CELL, animated: false });
      const jumpedAt = performance.now();
      waitFor(() => times.settled(lastScreen) === lastScreen.length, SCENARIO_TIMEOUT_MS).then(
        (ok) => {
          if (cancelled) return;
          const lastLoad = Math.max(...lastScreen.map((i) => times.loadedAt(i) ?? 0));
          report(run, {
            timedOut: !ok,
            lastScreenMs: lastLoad > 0 ? Math.round(lastLoad - jumpedAt) : null,
            ...times.summary(),
          });
        }
      );
    }, 300);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
    // Once per launch.
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);

  return (
    <FlashList
      ref={list}
      data={data}
      numColumns={COLUMNS}
      keyExtractor={(i) => String(i)}
      renderItem={({ item }) => <Cell run={run} index={item} times={times} />}
    />
  );
}

// --- Scenario: offline ---------------------------------------------------
//
// Starts with the fixture server stopped (the script's job): every image of
// one screen fails. The app logs TURBOIMAGE_BENCH_OFFLINE, the script starts
// the server, and the app polls it; once it answers, the screen is mounted
// again (neither library retries a failed view on its own). Measures how
// long recovery takes and whether any failure sticks (a cached error, or a
// dead pooled connection).

function OfflineScenario({ run }: { run: Run }) {
  const times = useLoadTimes();
  const [attempt, setAttempt] = useState(0);
  const count = Math.min(FIRST_SCREEN, run.count);

  useEffect(() => {
    let cancelled = false;
    log('TURBOIMAGE_BENCH_READY');
    (async () => {
      const failedOffline = await waitFor(() => times.settled() === count, SCENARIO_TIMEOUT_MS);
      const offline = times.summary();
      log('TURBOIMAGE_BENCH_OFFLINE');
      // Poll until the server answers.
      const online = await new Promise<boolean>((resolve) => {
        const poll = () => {
          if (cancelled) return resolve(false);
          fetch(`${BASE}/__ping`).then(
            (r) => (r.ok ? resolve(true) : setTimeout(poll, 100)),
            () => setTimeout(poll, 100)
          );
        };
        poll();
      });
      if (!online) return;
      if (cancelled) return;
      times.restart();
      setAttempt(1);
      const ok = await waitFor(() => times.settled() === count, SCENARIO_TIMEOUT_MS);
      report(run, {
        timedOut: !ok || !failedOffline,
        count,
        offlineFailed: offline.failed,
        offlineLoaded: offline.loaded,
        // After the server is back: loaded, failed, and how long it took.
        ...times.summary(),
      });
    })();
    return () => {
      cancelled = true;
    };
    // Once per launch.
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);

  return (
    <View key={attempt} style={styles.wrap}>
      {indicesFrom(0, count).map((i) => (
        <Cell key={i} run={run} index={i} times={times} />
      ))}
    </View>
  );
}

const SCENARIOS: Record<ScenarioName, (props: { run: Run }) => ReactNode> = {
  load: LoadScenario,
  grid: GridScenario,
  remount: RemountScenario,
  cancel: CancelScenario,
  offline: OfflineScenario,
};

// --- Launching -----------------------------------------------------------

// Parsed by hand to avoid relying on the runtime's URL implementation.
function parseRun(url: string | null): Run | null {
  if (url === null) return null;
  const param = (key: string) => url.match(new RegExp(`[?&]${key}=([^&]+)`))?.[1] ?? null;
  const lib = param('lib');
  const scenario = param('scenario') as ScenarioName | null;
  const source = (param('source') ?? 'photo') as SourceName;
  const urls = (param('urls') ?? 'unique') as UrlsName;
  const speed = param('speed') ?? 'paced';
  const count = Number(param('n') ?? (scenario === 'grid' ? 900 : 30));
  if (!isLibraryName(lib)) return null;
  if (scenario === null || !(scenario in SCENARIOS)) return null;
  if (!(source in SOURCE_PATH)) return null;
  if (urls !== 'unique' && urls !== 'repeated') return null;
  if (speed !== 'paced' && speed !== 'fast') return null;
  if (!Number.isInteger(count) || count < 1) return null;
  return { lib, scenario, source, urls, count, speed };
}

export default function App() {
  // `undefined` while the initial URL is being read; `null` for no run.
  const [run, setRun] = useState<Run | null | undefined>(undefined);

  useEffect(() => {
    // iOS scripts pass the link as `-launchURL` (NSUserDefaults' argument
    // domain, read through RN's Settings): `simctl openurl` asks to confirm.
    const launchArgument = Platform.OS === 'ios' ? Settings.get('launchURL') : undefined;
    Linking.getInitialURL().then(
      (url) =>
        setRun(parseRun(url ?? (typeof launchArgument === 'string' ? launchArgument : null))),
      () => setRun(null)
    );
  }, []);

  if (run === undefined) return <View style={styles.screen} />;
  if (run === null) return <Menu onPick={setRun} />;
  const Scenario = SCENARIOS[run.scenario];
  return (
    <View style={styles.screen}>
      <Scenario run={run} />
    </View>
  );
}

// For running by hand (e.g. under a profiler); results still go to the log.
function Menu({ onPick }: { onPick: (run: Run) => void }) {
  const runs: Run[] = [];
  for (const lib of Object.keys(LIBRARIES) as LibraryName[]) {
    for (const [scenario, extra] of [
      ['load', { count: 100 }],
      ['grid', { count: 900, speed: 'fast' }],
      ['grid', { count: 900, speed: 'fast', urls: 'repeated' }],
      ['remount', {}],
      ['cancel', { source: 'slow' }],
    ] as const) {
      runs.push({
        lib,
        scenario,
        source: 'photo',
        urls: 'unique',
        count: 30,
        speed: 'paced',
        ...extra,
      });
    }
  }
  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.menu}>
      {runs.map((r) => (
        <Pressable
          key={`${r.lib}-${r.scenario}-${r.source}-${r.urls}-${r.speed}`}
          onPress={() => onPick(r)}
          style={styles.item}
        >
          <Text style={styles.itemText}>
            {`${r.lib} · ${r.scenario} · ${r.source} · ${r.urls} · n=${r.count}`}
          </Text>
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
