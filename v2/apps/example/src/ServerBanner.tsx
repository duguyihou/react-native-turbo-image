// Every remote image in the app needs the fixture server. Without it, each
// demo fails with code 'network', which looks like a TurboImage bug, so the
// screens say what is wrong before anyone goes looking.
import { useCallback, useEffect, useState } from 'react';
import { Platform, StyleSheet, Text, View } from 'react-native';
import { BASE, isServerReachable } from './fixtures';
import { MONOSPACE, useTheme } from './theme';
import { Button } from './ui';

type Status = 'checking' | 'reachable' | 'unreachable';

export function useServerStatus() {
  const [status, setStatus] = useState<Status>('checking');
  const ping = useCallback(
    () => isServerReachable().then((ok) => setStatus(ok ? 'reachable' : 'unreachable')),
    []
  );
  useEffect(() => {
    ping();
  }, [ping]);
  const check = () => {
    setStatus('checking');
    ping();
  };
  return { status, check };
}

// Nothing while reachable, unless `always` (Home shows a one-line status).
export function ServerBanner({ always = false }: { always?: boolean }) {
  const theme = useTheme();
  const { status, check } = useServerStatus();
  if (status === 'reachable' || status === 'checking') {
    return always ? (
      <Text style={[styles.ok, { color: theme.secondaryText }]}>
        Fixture server {status === 'checking' ? '…' : `reachable at ${BASE}`}
      </Text>
    ) : null;
  }
  return (
    <View style={[styles.banner, { borderColor: theme.danger }]}>
      <Text style={[styles.title, { color: theme.danger }]}>Fixture server not reachable</Text>
      <Text style={[styles.body, { color: theme.text }]}>
        Remote images come from a local server. In the repository's v2/ folder, run:
      </Text>
      <Text style={[styles.command, { color: theme.text }]} selectable>
        bun run fixtures
      </Text>
      {Platform.OS === 'android' && (
        <Text style={[styles.body, { color: theme.text }]}>
          It also runs `adb reverse tcp:8765 tcp:8765`, which this device needs to reach {BASE}.
          Re-run it after the emulator restarts.
        </Text>
      )}
      <View style={styles.row}>
        <Button title="Check again" onPress={check} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  ok: { fontSize: 13, textAlign: 'center' },
  banner: { borderWidth: 1, borderRadius: 12, padding: 16, gap: 8 },
  title: { fontSize: 15, fontWeight: '600' },
  body: { fontSize: 14, lineHeight: 19 },
  command: { fontFamily: MONOSPACE, fontSize: 14 },
  row: { flexDirection: 'row' },
});
