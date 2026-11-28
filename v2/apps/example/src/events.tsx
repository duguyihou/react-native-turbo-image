// Records a <TurboImage>'s load events for display, timed from each onStart.
// Every load is: onStart → onProgress* → (onSuccess | onFailure) →
// onCompletion, and a load superseded by a new source ends with
// onCompletion { state: 'cancelled' } alone.
import { useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import type {
  CompletionEvent,
  FailureEvent,
  ProgressEvent,
  SuccessEvent,
} from 'react-native-turbo-image';
import { MONOSPACE, useTheme } from './theme';

// React Native has `performance.now()`, but its type definitions omit it.
declare const performance: { now(): number };

type NativeEvent<T> = { nativeEvent: T };

type Entry = { key: number; text: string; progressEvents?: number };

const MAX_ENTRIES = 40;

const kilobytes = (bytes: number) => `${Math.round(bytes / 1024)} KB`;

export function useEventLog({ progress = true }: { progress?: boolean } = {}) {
  const [entries, setEntries] = useState<Entry[]>([]);
  const startedAt = useRef(0);
  const nextKey = useRef(0);

  const elapsed = () => `+${Math.round(performance.now() - startedAt.current)} ms`.padEnd(9);

  const append = (text: string) => {
    const key = nextKey.current++;
    setEntries((previous) => [...previous, { key, text }].slice(-MAX_ENTRIES));
  };

  const handlers = {
    onStart: () => {
      startedAt.current = performance.now();
      append(`${elapsed()} onStart`);
    },
    // Up to ~100 per load: they update one line instead of adding 100.
    onProgress: ({ nativeEvent: { completed, total } }: NativeEvent<ProgressEvent>) => {
      const text = `${elapsed()} onProgress ${kilobytes(completed)} of ${
        total < 0 ? 'unknown' : kilobytes(total)
      }`;
      setEntries((previous) => {
        const last = previous[previous.length - 1];
        if (last?.progressEvents !== undefined) {
          const count = last.progressEvents + 1;
          return [
            ...previous.slice(0, -1),
            { ...last, text: `${text} (${count} events)`, progressEvents: count },
          ];
        }
        const key = nextKey.current++;
        return [...previous, { key, text: `${text} (1 event)`, progressEvents: 1 }].slice(
          -MAX_ENTRIES
        );
      });
    },
    onSuccess: ({ nativeEvent: { width, height } }: NativeEvent<SuccessEvent>) =>
      append(`${elapsed()} onSuccess ${width}×${height} px`),
    onFailure: ({ nativeEvent: { code, error } }: NativeEvent<FailureEvent>) =>
      append(`${elapsed()} onFailure '${code}': ${error}`),
    onCompletion: ({ nativeEvent: { state } }: NativeEvent<CompletionEvent>) =>
      append(`${elapsed()} onCompletion ${state}`),
  };

  // An `onProgress` handler turns progress tracking on for the load, so it
  // is attached only when asked for (see `progressEnabled` in the library).
  const { onProgress, ...withoutProgress } = handlers;
  return {
    entries,
    handlers: progress ? { ...withoutProgress, onProgress } : withoutProgress,
    // A line from the app itself, such as "remounted", between loads.
    mark: (text: string) => append(`— ${text}`),
    clear: () => setEntries([]),
  };
}

export function EventLog({ entries }: { entries: Entry[] }) {
  const theme = useTheme();
  return (
    <View
      style={[styles.log, { backgroundColor: theme.dark ? '#000000' : '#f2f2f7' }]}
      accessibilityLabel="Event log"
    >
      {entries.length === 0 ? (
        <Text style={[styles.line, { color: theme.secondaryText }]}>No events yet.</Text>
      ) : (
        entries.map((entry) => (
          <Text key={entry.key} style={[styles.line, { color: theme.text }]} selectable>
            {entry.text}
          </Text>
        ))
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  log: { borderRadius: 8, padding: 10, gap: 2 },
  line: { fontFamily: MONOSPACE, fontSize: 11, lineHeight: 15 },
});
