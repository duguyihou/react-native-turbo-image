// One image and everything that happens to it: the event log, the cache
// policy, the cache module's calls, and the processors. The sources cover
// request headers, animated formats and every failure code.
import { useState } from 'react';
import { StyleSheet } from 'react-native';
import { TurboImage } from 'react-native-turbo-image';
import type { CachePolicy, TurboImageProps } from 'react-native-turbo-image';
import { EventLog, useEventLog } from '../events';
import { DEMO_SOURCES, demoSource } from '../fixtures';
import { ServerBanner } from '../ServerBanner';
import { useTheme } from '../theme';
import { Button, ButtonRow, Caption, Choice, Code, Screen, Section } from '../ui';

// React Native has `performance.now()`, but its type definitions omit it.
declare const performance: { now(): number };

const CACHE_POLICIES: CachePolicy[] = ['default', 'memoryOnly', 'noCache', 'cacheOnly', 'urlCache'];

const POLICY_NOTES: Record<CachePolicy, string> = {
  default: 'Memory, then the disk cache, then the network.',
  memoryOnly: 'Memory, then the network; nothing is written to disk.',
  noCache: 'Always the network; the result is not cached.',
  cacheOnly: "Memory and disk only; a miss fails with 'notCached'.",
  urlCache:
    'The platform HTTP cache, which obeys Cache-Control and ETags. It is a separate store: cacheOnly cannot see it.',
};

// Processors run in this order: resize, blur, monochrome, tint. Each
// processed variant is a separate memory-cache entry; disk keeps the original.
const TRANSFORMS = {
  none: {},
  resize: { resize: 80 },
  blur: { blur: 8 },
  monochrome: { monochrome: 'white' },
  tint: { tint: '#2060c0' },
  'resize + blur': { resize: 80, blur: 4 },
} satisfies Record<string, Pick<TurboImageProps, 'resize' | 'blur' | 'monochrome' | 'tint'>>;
type TransformName = keyof typeof TRANSFORMS;

export function DetailScreen({
  initialSourceId,
  onBack,
}: {
  initialSourceId?: string;
  onBack: () => void;
}) {
  const theme = useTheme();
  const [demo, setDemo] = useState(() => demoSource(initialSourceId ?? 'photo'));
  const [cachePolicy, setCachePolicy] = useState<CachePolicy>(demo.cachePolicy ?? 'default');
  const [transform, setTransform] = useState<TransformName>('none');
  // A new key remounts the view: a fresh load, as when a screen is reopened.
  const [mountKey, setMountKey] = useState(0);
  const [callResult, setCallResult] = useState('');
  const log = useEventLog();

  const chooseSource = (id: string) => {
    const next = demoSource(id);
    setDemo(next);
    setCachePolicy(next.cachePolicy ?? 'default');
  };

  // Runs a TurboImage static and shows how it went.
  const call = async (name: string, run: () => Promise<unknown>) => {
    setCallResult(`${name}…`);
    const startedAt = performance.now();
    try {
      const result = await run();
      const ms = Math.round(performance.now() - startedAt);
      setCallResult(
        `${name} → ${result === undefined ? 'done' : JSON.stringify(result)} (${ms} ms)`
      );
    } catch (error) {
      // getSize rejects with onFailure's codes; `dispose` and
      // `clearDiskCache` with 'disk' on Android disk errors.
      const code = (error as { code?: string }).code;
      setCallResult(`${name} rejected: ${code ?? ''} ${(error as Error).message}`);
    }
  };

  const transformProps = TRANSFORMS[transform];
  const usage = [
    '<TurboImage',
    `  source={${JSON.stringify(demo.source)}}`,
    cachePolicy !== 'default' && `  cachePolicy="${cachePolicy}"`,
    ...Object.entries(transformProps).map(
      ([prop, value]) => `  ${prop}={${JSON.stringify(value)}}`
    ),
    '  onStart={…} onProgress={…} onSuccess={…}',
    '  onFailure={…} onCompletion={…}',
    '/>',
  ]
    .filter(Boolean)
    .join('\n');

  return (
    <Screen title="Image detail" onBack={onBack}>
      <ServerBanner />
      <Choice
        options={DEMO_SOURCES.map((d) => [d.id, d.label] as const)}
        value={demo.id}
        onChange={chooseSource}
      />
      <TurboImage
        key={mountKey}
        style={[styles.image, { backgroundColor: theme.imageBackground }]}
        source={demo.source}
        cachePolicy={cachePolicy}
        {...transformProps}
        {...log.handlers}
      />
      <Caption>{demo.note}</Caption>

      <Section
        title="Events"
        caption="Changing the source while a load runs ends that load with onCompletion 'cancelled'."
      >
        <EventLog entries={log.entries} />
        <ButtonRow>
          <Button
            title="Remount"
            onPress={() => {
              log.mark('remounted');
              setMountKey((n) => n + 1);
            }}
          />
          <Button title="Clear log" onPress={log.clear} />
        </ButtonRow>
      </Section>

      <Section title="Cache policy" caption={POLICY_NOTES[cachePolicy]}>
        <Choice options={CACHE_POLICIES} value={cachePolicy} onChange={setCachePolicy} />
        <Caption>
          The memory cache is shared by every policy. After Clear memory, a remount shows what the
          policy does on its own.
        </Caption>
      </Section>

      <Section
        title="Cache module"
        caption="TurboImage's statics, called with this source and policy. prefetch downloads to disk without decoding; getSize reads only the file header."
      >
        <ButtonRow>
          <Button
            title="prefetch"
            onPress={() =>
              call('prefetch', () => TurboImage.prefetch([demo.source], { cachePolicy }))
            }
          />
          <Button
            title="getSize"
            onPress={() => call('getSize', () => TurboImage.getSize(demo.source, cachePolicy))}
          />
          <Button
            title="dispose"
            onPress={() => call('dispose', () => TurboImage.dispose([demo.source]))}
          />
          <Button
            title="Clear memory"
            onPress={() => call('clearMemoryCache', TurboImage.clearMemoryCache)}
          />
          <Button
            title="Clear disk"
            onPress={() => call('clearDiskCache', TurboImage.clearDiskCache)}
          />
        </ButtonRow>
        {callResult !== '' && <Code>{callResult}</Code>}
      </Section>

      <Section
        title="Transformations"
        caption="resize is a width in points; blur a sigma in image pixels; monochrome maps luminance onto a colour; tint fills the opaque area. onSuccess reports the processed size."
      >
        <Choice
          options={Object.keys(TRANSFORMS) as TransformName[]}
          value={transform}
          onChange={setTransform}
        />
      </Section>

      <Section title="Usage">
        <Code>{usage}</Code>
      </Section>
    </Screen>
  );
}

const styles = StyleSheet.create({
  image: { width: '100%', aspectRatio: 3 / 2, borderRadius: 12 },
});
