// Every public prop of <TurboImage>, with the JSX for the current settings.
// Only what the 2.0 API has; the deprecated 1.x props (`rounded`,
// `indicator`, `format`, `isProgressiveImageRenderingEnabled`,
// `placeholder.memoryCacheKey`) are left out on purpose. `recyclingKey`
// is too: it only matters in a recycling list.
import { useState } from 'react';
import { Platform, StyleSheet } from 'react-native';
import { TurboImage } from 'react-native-turbo-image';
import type {
  CachePolicy,
  ContentPosition,
  ResizeMode,
  TurboImageProps,
} from 'react-native-turbo-image';
import { EventLog, useEventLog } from '../events';
import { BLURHASH, DEMO_SOURCES, THUMBHASH, demoSource, photoUrl } from '../fixtures';
import { ServerBanner } from '../ServerBanner';
import { useTheme } from '../theme';
import { Button, ButtonRow, Choice, Code, Screen, Section, Toggle } from '../ui';

const RESIZE_MODES: ResizeMode[] = ['contain', 'cover', 'stretch', 'center', 'scale-down'];
const POSITIONS: ContentPosition[] = ['center', 'top', 'bottom', 'left', 'right', 'top left'];
const CACHE_POLICIES: CachePolicy[] = ['default', 'memoryOnly', 'noCache', 'cacheOnly', 'urlCache'];
const PLACEHOLDERS = {
  none: undefined,
  blurhash: { blurhash: BLURHASH },
  thumbhash: { thumbhash: THUMBHASH },
  uri: { uri: photoUrl('photo') },
} satisfies Record<string, TurboImageProps['placeholder']>;
type PlaceholderName = keyof typeof PLACEHOLDERS;

// The frame's shape, to see what the resize modes and positions do.
const FRAMES = { '3:2': 3 / 2, '1:1': 1, '2:3': 2 / 3 } as const;
type FrameName = keyof typeof FRAMES;

type Settings = {
  sourceId: string;
  resizeMode: ResizeMode;
  contentPosition: ContentPosition;
  cachePolicy: CachePolicy;
  placeholder: PlaceholderName;
  showPlaceholderOnFailure: boolean;
  fadeDuration: number;
  resize: number;
  blur: number;
  monochrome: string;
  tint: string;
  allowDownscaling: boolean;
  allowHardware: boolean;
  enableLiveTextInteraction: boolean;
  borderRadius: number;
  frame: FrameName;
};

// The library's defaults, so the JSX lists only what differs.
const DEFAULTS: Settings = {
  sourceId: 'photo',
  resizeMode: 'contain',
  contentPosition: 'center',
  cachePolicy: 'default',
  placeholder: 'none',
  showPlaceholderOnFailure: false,
  fadeDuration: 300,
  resize: 0,
  blur: 0,
  monochrome: '',
  tint: '',
  allowDownscaling: true,
  allowHardware: true,
  enableLiveTextInteraction: false,
  borderRadius: 0,
  frame: '3:2',
};

function usageJsx(settings: Settings): string {
  const demo = demoSource(settings.sourceId);
  const lines = [`  source={${JSON.stringify(demo.source)}}`];
  lines.push(
    `  style={{ width: '100%', aspectRatio: ${FRAMES[settings.frame].toFixed(2)}${
      settings.borderRadius ? `, borderRadius: ${settings.borderRadius}` : ''
    } }}`
  );
  const differs = <K extends keyof Settings>(key: K) => settings[key] !== DEFAULTS[key];
  const prop = (name: string, value: unknown) =>
    lines.push(
      value === true
        ? `  ${name}`
        : `  ${name}=${typeof value === 'string' ? `"${value}"` : `{${JSON.stringify(value)}}`}`
    );
  if (differs('resizeMode')) prop('resizeMode', settings.resizeMode);
  if (differs('contentPosition')) prop('contentPosition', settings.contentPosition);
  if (differs('cachePolicy')) prop('cachePolicy', settings.cachePolicy);
  if (differs('placeholder')) prop('placeholder', PLACEHOLDERS[settings.placeholder]);
  if (differs('showPlaceholderOnFailure')) prop('showPlaceholderOnFailure', true);
  if (differs('fadeDuration')) prop('fadeDuration', settings.fadeDuration);
  if (differs('resize')) prop('resize', settings.resize);
  if (differs('blur')) prop('blur', settings.blur);
  if (differs('monochrome')) prop('monochrome', settings.monochrome);
  if (differs('tint')) prop('tint', settings.tint);
  if (differs('allowDownscaling')) prop('allowDownscaling', false);
  if (differs('allowHardware')) prop('allowHardware', false);
  if (differs('enableLiveTextInteraction')) prop('enableLiveTextInteraction', true);
  return ['<TurboImage', ...lines, '/>'].join('\n');
}

export function PlaygroundScreen({ onBack }: { onBack: () => void }) {
  const theme = useTheme();
  const [settings, setSettings] = useState<Settings>(DEFAULTS);
  const [mountKey, setMountKey] = useState(0);
  const log = useEventLog({ progress: false });
  const set =
    <K extends keyof Settings>(key: K) =>
    (value: Settings[K]) =>
      setSettings((current) => ({ ...current, [key]: value }));

  const demo = demoSource(settings.sourceId);

  return (
    <Screen title="Playground" onBack={onBack}>
      <ServerBanner />
      <TurboImage
        key={mountKey}
        style={[
          styles.image,
          {
            aspectRatio: FRAMES[settings.frame],
            borderRadius: settings.borderRadius,
            backgroundColor: theme.imageBackground,
          },
        ]}
        source={demo.source}
        resizeMode={settings.resizeMode}
        contentPosition={settings.contentPosition}
        cachePolicy={settings.cachePolicy}
        placeholder={PLACEHOLDERS[settings.placeholder]}
        showPlaceholderOnFailure={settings.showPlaceholderOnFailure}
        fadeDuration={settings.fadeDuration}
        resize={settings.resize}
        blur={settings.blur}
        monochrome={settings.monochrome || undefined}
        tint={settings.tint || undefined}
        allowDownscaling={settings.allowDownscaling}
        allowHardware={settings.allowHardware}
        enableLiveTextInteraction={settings.enableLiveTextInteraction}
        {...log.handlers}
      />
      <ButtonRow>
        <Button
          title="Remount"
          onPress={() => {
            log.mark('remounted');
            setMountKey((n) => n + 1);
          }}
        />
        <Button title="Reset" onPress={() => setSettings(DEFAULTS)} />
      </ButtonRow>

      <Section title="JSX">
        <Code>{usageJsx(settings)}</Code>
      </Section>

      <Section title="Events" caption="onProgress is left off here; see Image detail.">
        <EventLog entries={log.entries} />
      </Section>

      <Section title="Source">
        <Choice
          options={DEMO_SOURCES.map((d) => [d.id, d.label] as const)}
          value={settings.sourceId}
          onChange={set('sourceId')}
        />
        <Choice
          label="cachePolicy"
          options={CACHE_POLICIES}
          value={settings.cachePolicy}
          onChange={set('cachePolicy')}
        />
      </Section>

      <Section title="Layout">
        <Choice
          label="resizeMode"
          options={RESIZE_MODES}
          value={settings.resizeMode}
          onChange={set('resizeMode')}
        />
        <Choice
          label="contentPosition"
          options={POSITIONS as string[]}
          value={settings.contentPosition as string}
          onChange={(value) => set('contentPosition')(value as ContentPosition)}
        />
        <Choice
          label="Frame"
          options={Object.keys(FRAMES) as FrameName[]}
          value={settings.frame}
          onChange={set('frame')}
        />
        <Choice
          label="style.borderRadius"
          options={[0, 16, 9999]}
          value={settings.borderRadius}
          onChange={set('borderRadius')}
        />
      </Section>

      <Section title="Placeholder">
        <Choice
          label="placeholder"
          options={Object.keys(PLACEHOLDERS) as PlaceholderName[]}
          value={settings.placeholder}
          onChange={set('placeholder')}
        />
        <Toggle
          label="showPlaceholderOnFailure"
          value={settings.showPlaceholderOnFailure}
          onChange={set('showPlaceholderOnFailure')}
        />
        <Choice
          label="fadeDuration (ms)"
          options={[0, 300, 1000]}
          value={settings.fadeDuration}
          onChange={set('fadeDuration')}
        />
      </Section>

      <Section
        title="Processing"
        caption="Applied in this order; each combination is its own memory-cache entry."
      >
        <Choice
          label="resize (points)"
          options={[0, 60, 150]}
          value={settings.resize}
          onChange={set('resize')}
        />
        <Choice
          label="blur (sigma, px)"
          options={[0, 2, 8, 20]}
          value={settings.blur}
          onChange={set('blur')}
        />
        <Choice
          label="monochrome"
          options={[
            ['', 'off'],
            ['white', 'white'],
            ['#2060c0', '#2060c0'],
          ]}
          value={settings.monochrome}
          onChange={set('monochrome')}
        />
        <Choice
          label="tint"
          options={[
            ['', 'off'],
            ['#e63946', '#e63946'],
            ['#2060c0', '#2060c0'],
          ]}
          value={settings.tint}
          onChange={set('tint')}
        />
      </Section>

      <Section title="Decoding">
        <Toggle
          label="allowDownscaling"
          note="Decode no larger than the view. Turn off for images zoomed with a transform."
          value={settings.allowDownscaling}
          onChange={set('allowDownscaling')}
        />
        <Toggle
          label="allowHardware"
          note={
            Platform.OS === 'android'
              ? 'Off: a software bitmap, needed only to read pixels.'
              : 'Android only; no effect on iOS.'
          }
          value={settings.allowHardware}
          onChange={set('allowHardware')}
        />
        <Toggle
          label="enableLiveTextInteraction"
          note={
            Platform.OS === 'ios'
              ? 'VisionKit Live Text: long-press text in the image.'
              : 'iOS only; no effect on Android.'
          }
          value={settings.enableLiveTextInteraction}
          onChange={set('enableLiveTextInteraction')}
        />
      </Section>
    </Screen>
  );
}

const styles = StyleSheet.create({
  image: { width: '100%' },
});
