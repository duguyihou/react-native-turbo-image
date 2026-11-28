// Reproducible stress scenarios for lists of images. What this screen
// measures, and how:
//   - Load events, counted from every cell's handlers (JS).
//   - Time from the list's mount to its first and last onSuccess (JS clock;
//     it includes the time events take to reach JS).
//   - JS-thread frames during the scripted scroll (JS clock, one
//     requestAnimationFrame per step). Not the UI thread's frame rate.
//   - Requests that reached the fixture server, and bodies it was still
//     sending when the client hung up (`/__hits`): request reuse and
//     cancellation, seen from the server.
// What it does not measure: UI-thread FPS, memory, or which cache tier
// served a load. The README says which tools measure those.
//
// Every dataset is a fixed list of URLs (no random or per-run names), so a
// second run of a dataset is a warm-cache run and a run after "Clear disk"
// and "Clear memory" is a cold one.
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ComponentRef, RefObject } from 'react';
import { Dimensions, FlatList, ScrollView, StyleSheet, Text, View } from 'react-native';
import { TurboImage } from 'react-native-turbo-image';
import type { CompletionEvent, FailureEvent } from 'react-native-turbo-image';
import { BASE, serverHits } from '../fixtures';
import type { ServerHits } from '../fixtures';
import { ServerBanner } from '../ServerBanner';
import { MONOSPACE, useTheme } from '../theme';
import { Button, ButtonRow, Caption, Choice, Screen, Stat } from '../ui';

// React Native has `performance.now()`, but its type definitions omit it.
declare const performance: { now(): number };

// --- Datasets --------------------------------------------------------------

const COUNTS = [100, 500, 1000] as const;
type Count = (typeof COUNTS)[number];

const DATASETS = {
  // N distinct 600×400 JPEGs (28 KB each): a feed.
  unique: { label: 'Unique', path: (i: number) => `/photo/perf-u-${i}.jpg` },
  // The same 12 URLs over and over: an avatar list. With working reuse, the
  // server sees about 12 requests however many rows there are.
  repeated: { label: 'Repeated ×12', path: (i: number) => `/photo/perf-r-${i % 12}.jpg` },
  // N distinct 3000×2000 JPEGs (368 KB each), decoded at the cell's size.
  large: { label: '3000×2000', path: (i: number) => `/large/perf-l-${i}.jpg` },
  // N distinct 3000×2000 JPEGs sent over about 2 s each: scrolling past
  // them cancels loads mid-body, which the server counts as aborted.
  slow: { label: 'Slow', path: (i: number) => `/slow/large/perf-s-${i}.jpg` },
} as const;
type Dataset = keyof typeof DATASETS;

// The prefix all of a dataset's paths share, for the server's counts.
const prefixOf = (dataset: Dataset) => DATASETS[dataset].path(0).replace(/0\.jpg$/, '');

export type PerformanceParams = {
  count: Count;
  dataset: Dataset;
  // Starts a scenario once the list is mounted, then logs a
  // `TURBOIMAGE_PERF {...}` line (for scripted runs).
  autorun?: 'scroll' | 'remount';
};

const DEFAULT_PARAMS: PerformanceParams = { count: 100, dataset: 'unique' };

// From a deep link's query: count=1000&dataset=repeated&autorun=scroll.
export function parsePerformanceParams(query: Record<string, string>): PerformanceParams {
  const count = Number(query.count);
  const dataset = query.dataset as Dataset;
  return {
    count: (COUNTS as readonly number[]).includes(count) ? (count as Count) : DEFAULT_PARAMS.count,
    dataset: dataset in DATASETS ? dataset : DEFAULT_PARAMS.dataset,
    autorun: query.autorun === 'scroll' || query.autorun === 'remount' ? query.autorun : undefined,
  };
}

const COLUMNS = 3;
const CELL = Math.floor(Dimensions.get('window').width / COLUMNS);

// --- Counters --------------------------------------------------------------

// Mutated by the cells' handlers; read by the stats panel twice a second.
// A ref, not state: 1000 cells setting state per event would measure React.
type Counters = {
  mountedAt: number;
  starts: number;
  successes: number;
  failures: Record<string, number>;
  cancelled: number;
  completed: number;
  firstSuccessMs: number | null;
  lastSuccessMs: number | null;
};

const newCounters = (): Counters => ({
  mountedAt: performance.now(),
  starts: 0,
  successes: 0,
  failures: {},
  cancelled: 0,
  completed: 0,
  firstSuccessMs: null,
  lastSuccessMs: null,
});

type Handlers = {
  onStart: () => void;
  onSuccess: () => void;
  onFailure: (event: { nativeEvent: FailureEvent }) => void;
  onCompletion: (event: { nativeEvent: CompletionEvent }) => void;
};

// No onProgress: a handler would turn progress tracking on for every load.
function useCounters() {
  const counters = useRef<Counters>(newCounters());
  const handlers = useMemo<Handlers>(
    () => ({
      onStart: () => {
        counters.current.starts++;
      },
      onSuccess: () => {
        const c = counters.current;
        const ms = Math.round(performance.now() - c.mountedAt);
        c.successes++;
        c.firstSuccessMs ??= ms;
        c.lastSuccessMs = ms;
      },
      onFailure: ({ nativeEvent: { code } }) => {
        const failures = counters.current.failures;
        failures[code] = (failures[code] ?? 0) + 1;
      },
      onCompletion: ({ nativeEvent: { state } }) => {
        if (state === 'cancelled') counters.current.cancelled++;
        else counters.current.completed++;
      },
    }),
    []
  );
  // Timings are since the latest mount; event counts run on until a reset.
  const markMounted = useCallback(() => {
    const c = counters.current;
    c.mountedAt = performance.now();
    c.firstSuccessMs = null;
    c.lastSuccessMs = null;
  }, []);
  return { counters, handlers, markMounted };
}

// --- Screen ----------------------------------------------------------------

type ScrollResult = { frames: number; ms: number };

export function PerformanceScreen({
  initialParams = DEFAULT_PARAMS,
  onBack,
}: {
  initialParams?: PerformanceParams;
  onBack: () => void;
}) {
  const theme = useTheme();
  const [count, setCount] = useState<Count>(initialParams.count);
  const [dataset, setDataset] = useState<Dataset>(initialParams.dataset);
  // Screens per frame for the scripted scroll.
  const [speed, setSpeed] = useState(1);
  // A new key remounts the list; `mounted` false shows it empty. Starts
  // unmounted: the server's baseline is read before the first request.
  const [listKey, setListKey] = useState(0);
  const [mounted, setMounted] = useState(false);
  const [busy, setBusy] = useState<'scrolling' | 'remounting' | null>(null);
  const [scrollResult, setScrollResult] = useState<ScrollResult | null>(null);
  const [server, setServer] = useState<ServerHits | 'unreachable' | null>(null);
  const serverBaseline = useRef<ServerHits | null>(null);
  const { counters, handlers, markMounted } = useCounters();
  const list = useRef<ComponentRef<typeof FlatList<string>>>(null);
  const viewportHeight = useRef(0);
  const stopScroll = useRef<(() => void) | null>(null);
  const stopRemounts = useRef<(() => void) | null>(null);
  // Leaving the screen mid-scenario stops it.
  useEffect(
    () => () => {
      stopScroll.current?.();
      stopRemounts.current?.();
    },
    []
  );

  const urls = useMemo(
    () => Array.from({ length: count }, (_, i) => `${BASE}${DATASETS[dataset].path(i)}`),
    [count, dataset]
  );

  // The server's counts since the last reset.
  const refreshServer = useCallback(async () => {
    try {
      const now = await serverHits(prefixOf(dataset));
      const base = serverBaseline.current ?? { count: 0, conditional: 0, aborted: 0 };
      const delta = {
        count: now.count - base.count,
        conditional: now.conditional - base.conditional,
        aborted: now.aborted - base.aborted,
      };
      setServer(delta);
      return delta;
    } catch {
      setServer('unreachable');
      return null;
    }
  }, [dataset]);

  // Zero the counters and take the server's current counts as the baseline.
  const reset = useCallback(async () => {
    counters.current = newCounters();
    setScrollResult(null);
    try {
      serverBaseline.current = await serverHits(prefixOf(dataset));
      setServer({ count: 0, conditional: 0, aborted: 0 });
    } catch {
      serverBaseline.current = null;
      setServer('unreachable');
    }
  }, [counters, dataset]);

  // A new dataset or size is a new run, with a freshly mounted list.
  useEffect(() => {
    // A scenario still running belongs to the previous run.
    stopScroll.current?.();
    stopRemounts.current?.();
    setBusy(null);
    // The baseline must be read before the new list's first request.
    setMounted(false);
    reset().then(() => {
      markMounted();
      setListKey((k) => k + 1);
      setMounted(true);
    });
  }, [count, dataset, reset, markMounted]);

  // Scripted fast scroll: `speed` screens per frame to the end, then back to
  // the top. Fixed steps, so every run scrolls the same way.
  const startScroll = useCallback(
    (onDone?: (result: ScrollResult) => void) => {
      // Not laid out yet (the list is remounting): nothing to scroll.
      if (viewportHeight.current === 0) return;
      const rows = Math.ceil(count / COLUMNS);
      const end = Math.max(0, rows * CELL - viewportHeight.current);
      const step = Math.max(1, speed * viewportHeight.current);
      let offset = 0;
      let direction = 1;
      let frames = 0;
      let frame = 0;
      const startedAt = performance.now();
      setBusy('scrolling');
      const finish = (cancelled: boolean) => {
        cancelAnimationFrame(frame);
        stopScroll.current = null;
        setBusy(null);
        const result = { frames, ms: Math.round(performance.now() - startedAt) };
        if (!cancelled) {
          setScrollResult(result);
          onDone?.(result);
        }
        // Let the last cells' requests reach the server before counting.
        setTimeout(refreshServer, 1000);
      };
      const tick = () => {
        frames++;
        offset = Math.min(end, Math.max(0, offset + direction * step));
        list.current?.scrollToOffset({ offset, animated: false });
        if (offset >= end) direction = -1;
        if (direction === -1 && offset <= 0) {
          finish(false);
          return;
        }
        frame = requestAnimationFrame(tick);
      };
      stopScroll.current = () => finish(true);
      frame = requestAnimationFrame(tick);
    },
    [count, speed, refreshServer]
  );

  // Rapid mount/unmount, as when a user opens and leaves a screen quickly:
  // 20 cycles of one empty frame, then 250 ms mounted.
  const startRemounts = useCallback(
    (onDone?: () => void) => {
      setBusy('remounting');
      let cycle = 0;
      let timer: ReturnType<typeof setTimeout> | undefined;
      let frame = 0;
      const next = () => {
        if (cycle++ >= 20) {
          stopRemounts.current = null;
          setBusy(null);
          setTimeout(refreshServer, 1000);
          onDone?.();
          return;
        }
        setMounted(false);
        frame = requestAnimationFrame(() => {
          markMounted();
          setListKey((k) => k + 1);
          setMounted(true);
          timer = setTimeout(next, 250);
        });
      };
      stopRemounts.current = () => {
        clearTimeout(timer);
        cancelAnimationFrame(frame);
        stopRemounts.current = null;
      };
      next();
    },
    [markMounted, refreshServer]
  );

  // Deep-link autorun, once: a second after the first list has laid out.
  const autorun = useRef(initialParams.autorun);
  useEffect(() => {
    const scenario = autorun.current;
    if (!scenario) return undefined;
    autorun.current = undefined;
    const report = (extra: object) =>
      // After the 1 s refreshServer delay, so the counts are final.
      setTimeout(async () => {
        const c = counters.current;
        const hits = await refreshServer();
        // iOS release builds drop logs below error level; debug uses console.log
        // to avoid a LogBox toast (as the smoke test does).
        (__DEV__ ? console.log : console.error)(
          `TURBOIMAGE_PERF ${JSON.stringify({
            scenario,
            count,
            dataset,
            starts: c.starts,
            successes: c.successes,
            failures: c.failures,
            cancelled: c.cancelled,
            firstSuccessMs: c.firstSuccessMs,
            lastSuccessMs: c.lastSuccessMs,
            server: hits,
            ...extra,
          })}`
        );
      }, 1500);
    let timer: ReturnType<typeof setTimeout>;
    const start = () => {
      if (viewportHeight.current === 0) {
        timer = setTimeout(start, 250);
        return;
      }
      timer = setTimeout(
        () =>
          scenario === 'scroll'
            ? startScroll((result) => report({ scrollFrames: result.frames, scrollMs: result.ms }))
            : startRemounts(() => report({})),
        1000
      );
    };
    start();
    return () => clearTimeout(timer);
    // Once per screen: the deep link's parameters are the initial state.
    // oxlint-disable-next-line react/exhaustive-deps
  }, []);

  return (
    <Screen title="Performance" onBack={onBack} scroll={false}>
      <ScrollView
        style={[styles.panel, { borderBottomColor: theme.separator }]}
        contentContainerStyle={styles.panelContent}
      >
        <ServerBanner />
        <Choice
          options={COUNTS.map((n) => [n, `${n} images`] as const)}
          value={count}
          onChange={setCount}
        />
        <Choice
          options={(Object.keys(DATASETS) as Dataset[]).map((d) => [d, DATASETS[d].label] as const)}
          value={dataset}
          onChange={setDataset}
        />
        <ButtonRow>
          {busy === 'scrolling' ? (
            <Button title="Stop scrolling" onPress={() => stopScroll.current?.()} />
          ) : (
            <Button title="Fast scroll" disabled={busy !== null} onPress={() => startScroll()} />
          )}
          <Choice
            options={[
              [0.25, '¼'],
              [1, '1'],
              [3, '3'],
            ]}
            value={speed}
            onChange={setSpeed}
          />
          <Text style={[styles.unit, { color: theme.secondaryText }]}>screens/frame</Text>
        </ButtonRow>
        <ButtonRow>
          <Button title="Remount ×20" disabled={busy !== null} onPress={() => startRemounts()} />
          <Button
            title="Remount"
            disabled={busy !== null}
            onPress={() => {
              markMounted();
              setListKey((k) => k + 1);
            }}
          />
          <Button title="Clear memory" onPress={() => TurboImage.clearMemoryCache()} />
          <Button title="Clear disk" onPress={() => TurboImage.clearDiskCache()} />
          <Button title="Reset counts" onPress={reset} />
        </ButtonRow>
        <StatsPanel
          counters={counters}
          server={server}
          scrollResult={scrollResult}
          onRefreshServer={refreshServer}
          busy={busy}
        />
      </ScrollView>
      {mounted ? (
        <FlatList
          key={listKey}
          ref={list}
          data={urls}
          numColumns={COLUMNS}
          keyExtractor={(_, index) => String(index)}
          // With numColumns, FlatList's items are rows, so `index` is a row.
          getItemLayout={(_, index) => ({ length: CELL, offset: CELL * index, index })}
          renderItem={({ item, index }) => <Cell uri={item} index={index} handlers={handlers} />}
          onLayout={(e) => {
            viewportHeight.current = e.nativeEvent.layout.height;
          }}
          ListEmptyComponent={<Caption>No images.</Caption>}
        />
      ) : (
        <View style={styles.fill} />
      )}
    </Screen>
  );
}

// --- Cell ------------------------------------------------------------------

// Memoized with stable props, so the stats panel's ticks never re-render it.
const Cell = memo(function Cell({
  uri,
  index,
  handlers,
}: {
  uri: string;
  index: number;
  handlers: Handlers;
}) {
  const theme = useTheme();
  return (
    <View style={styles.cell}>
      <TurboImage
        style={[styles.cellImage, { backgroundColor: theme.imageBackground }]}
        source={{ uri }}
        resizeMode="cover"
        {...handlers}
      />
      {/* The row's index, to tell rows apart: every dataset is one photo. */}
      <Text style={styles.cellIndex}>{index}</Text>
    </View>
  );
});

// --- Stats -----------------------------------------------------------------

const ms = (value: number | null) => (value === null ? '–' : `${value} ms`);

function StatsPanel({
  counters,
  server,
  scrollResult,
  onRefreshServer,
  busy,
}: {
  counters: RefObject<Counters>;
  server: ServerHits | 'unreachable' | null;
  scrollResult: ScrollResult | null;
  onRefreshServer: () => void;
  busy: string | null;
}) {
  // Its own state, so only this panel re-renders twice a second.
  const [snapshot, setSnapshot] = useState<Counters>(() => ({ ...counters.current }));
  useEffect(() => {
    const timer = setInterval(
      () => setSnapshot({ ...counters.current, failures: { ...counters.current.failures } }),
      500
    );
    return () => clearInterval(timer);
  }, [counters]);

  const failures = Object.entries(snapshot.failures);
  const failureText =
    failures.length === 0 ? '0' : failures.map(([code, n]) => `${n} ${code}`).join(', ');
  const unfinished = snapshot.starts - snapshot.completed - snapshot.cancelled;

  return (
    <View style={styles.stats}>
      <Text style={styles.statsHeading}>Load events (JS)</Text>
      <Stat label="onStart / onSuccess" value={`${snapshot.starts} / ${snapshot.successes}`} />
      <Stat label="onFailure" value={failureText} />
      <Stat label="Completed as cancelled" value={snapshot.cancelled} />
      {/* Unmounted views send no events, so this is not "in flight". */}
      <Stat label="Starts with no completion yet" value={unfinished} />
      <Stat
        label="First / last onSuccess since mount"
        value={`${ms(snapshot.firstSuccessMs)} / ${ms(snapshot.lastSuccessMs)}`}
      />
      {scrollResult && (
        <Stat
          label="Scroll pass (JS frames)"
          value={`${scrollResult.frames} in ${scrollResult.ms} ms, ${(
            scrollResult.ms / scrollResult.frames
          ).toFixed(1)} ms each`}
        />
      )}
      <Text style={styles.statsHeading}>Fixture server</Text>
      {server === 'unreachable' ? (
        <Stat label="Requests" value="server unreachable" kind="unavailable" />
      ) : (
        <>
          <Stat label="Requests for this dataset" value={server?.count ?? '–'} />
          <Stat label="Bodies aborted by the client" value={server?.aborted ?? '–'} />
        </>
      )}
      <ButtonRow>
        <Button title="Refresh server counts" disabled={busy !== null} onPress={onRefreshServer} />
      </ButtonRow>
      <Text style={styles.statsHeading}>Not measured here</Text>
      <Stat label="UI frame rate, memory, cache tier" value="see README" kind="unavailable" />
    </View>
  );
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  // At most half the screen, so the list always has room; scrolls if taller.
  panel: { flexGrow: 0, maxHeight: '50%', borderBottomWidth: StyleSheet.hairlineWidth },
  panelContent: { padding: 12, gap: 8 },
  unit: { fontSize: 12, alignSelf: 'center' },
  stats: { gap: 2 },
  statsHeading: { fontSize: 12, fontWeight: '600', marginTop: 6, color: '#8e8e93' },
  cell: { width: CELL, height: CELL, padding: 1 },
  cellImage: { flex: 1 },
  cellIndex: {
    position: 'absolute',
    left: 4,
    bottom: 3,
    fontFamily: MONOSPACE,
    fontSize: 10,
    color: '#ffffff',
    textShadowColor: '#000000',
    textShadowRadius: 2,
  },
});
