// The everyday features, one small card each. Tap an image to open it on
// the Detail screen with its event log.
import { useState } from 'react';
import type { ReactNode } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import type { StyleProp, ViewStyle } from 'react-native';
import { TurboImage } from 'react-native-turbo-image';
import type { ResizeMode, Source } from 'react-native-turbo-image';
import type { Navigate } from '../../App';
import { BASE, BLURHASH, THUMBHASH, largeUrl, photoUrl, slowLargeUrl } from '../fixtures';
import { ServerBanner } from '../ServerBanner';
import { useTheme } from '../theme';
import { Button, ButtonRow, Screen, Section } from '../ui';

const RESIZE_MODES: ResizeMode[] = ['cover', 'contain', 'stretch', 'center', 'scale-down'];

export function GalleryScreen({ navigate, onBack }: { navigate: Navigate; onBack: () => void }) {
  const theme = useTheme();
  // Bumped by "Replay": a new key remounts the slow images, which load again.
  const [replay, setReplay] = useState(0);
  const open = (sourceId: string) => () => navigate({ name: 'detail', sourceId });
  const imageStyle = [styles.image, { backgroundColor: theme.imageBackground }];

  const replaySlowImages = async () => {
    // Cached after the first view, so they would appear at once.
    await TurboImage.clearMemoryCache();
    await TurboImage.clearDiskCache();
    setReplay((n) => n + 1);
  };

  return (
    <Screen title="Gallery" onBack={onBack}>
      <ServerBanner />

      <Section title="Remote and local">
        <View style={styles.row}>
          <Tile label="Remote URL" onPress={open('photo')}>
            <TurboImage style={imageStyle} source={{ uri: photoUrl('photo') }} resizeMode="cover" />
          </Tile>
          <Tile label="require() asset" onPress={open('local')}>
            <TurboImage
              style={imageStyle}
              source={require('../../assets/local-fixture.png')}
              resizeMode="cover"
            />
          </Tile>
        </View>
      </Section>

      <Section
        title="Dimensions"
        caption="Both are drawn in the same frame. TurboImage decodes no larger than the view, so the 3000×2000 photo costs about as much memory as the 600×400 one. The sizes below are onSuccess's, in pixels."
      >
        <View style={styles.row}>
          <DecodedSizeTile
            label="600×400"
            source={{ uri: photoUrl('photo') }}
            onPress={open('photo')}
          />
          <DecodedSizeTile
            label="3000×2000"
            source={{ uri: largeUrl('large') }}
            onPress={open('large')}
          />
        </View>
      </Section>

      <Section
        title="Resize modes"
        caption='A 3:2 photo in square frames. The default is "contain".'
      >
        <View style={styles.grid}>
          {RESIZE_MODES.map((mode) => (
            <Tile key={mode} label={mode} compact>
              <TurboImage
                style={[imageStyle, styles.square]}
                source={{ uri: photoUrl('photo') }}
                resizeMode={mode}
              />
            </Tile>
          ))}
        </View>
      </Section>

      <Section
        title="Placeholders"
        caption="Shown until the image arrives; these images take about 2 s. A blurhash or thumbhash is decoded from a short string; { uri } shows another image, such as a thumbnail already in the cache."
      >
        <View style={styles.row}>
          <Tile label="blurhash">
            <TurboImage
              key={`blurhash-${replay}`}
              style={imageStyle}
              source={{ uri: slowLargeUrl('placeholder-blurhash') }}
              placeholder={{ blurhash: BLURHASH }}
              resizeMode="cover"
            />
          </Tile>
          <Tile label="thumbhash">
            <TurboImage
              key={`thumbhash-${replay}`}
              style={imageStyle}
              source={{ uri: slowLargeUrl('placeholder-thumbhash') }}
              placeholder={{ thumbhash: THUMBHASH }}
              resizeMode="cover"
            />
          </Tile>
          <Tile label="{ uri }">
            <TurboImage
              key={`uri-${replay}`}
              style={imageStyle}
              source={{ uri: slowLargeUrl('placeholder-uri') }}
              placeholder={{ uri: photoUrl('photo') }}
              resizeMode="cover"
            />
          </Tile>
        </View>
        <ButtonRow>
          <Button title="Replay (clears both caches)" onPress={replaySlowImages} />
        </ButtonRow>
      </Section>

      <Section
        title="Rounded corners"
        caption="Plain borderRadius; 9999 makes a circle or pill. (The 1.x `rounded` prop is deprecated.)"
      >
        <View style={styles.row}>
          <Tile label="borderRadius: 12">
            <TurboImage
              style={[imageStyle, { borderRadius: 12 }]}
              source={{ uri: photoUrl('photo') }}
              resizeMode="cover"
            />
          </Tile>
          <Tile label="borderRadius: 9999">
            <TurboImage
              style={[imageStyle, styles.square, { borderRadius: 9999 }]}
              source={{ uri: photoUrl('photo') }}
              resizeMode="cover"
            />
          </Tile>
        </View>
      </Section>

      <Section
        title="Loading and errors"
        caption="A spinner driven by onStart and onCompletion (each start gets exactly one completion). On failure, keep the placeholder with showPlaceholderOnFailure, or draw your own state from onFailure."
      >
        <View style={styles.row}>
          <Tile label="Loading" onPress={open('slow')}>
            <LoadingImage
              key={`loading-${replay}`}
              style={imageStyle}
              source={{ uri: slowLargeUrl('loading') }}
            />
          </Tile>
          <Tile label="404, placeholder kept" onPress={open('missing')}>
            <LoadingImage
              style={imageStyle}
              source={{ uri: `${BASE}/missing/demo.jpg` }}
              placeholder={BLURHASH}
            />
          </Tile>
          <Tile label="Not an image" onPress={open('notAnImage')}>
            <LoadingImage style={imageStyle} source={{ uri: `${BASE}/not-an-image/demo` }} />
          </Tile>
        </View>
      </Section>
    </Screen>
  );
}

function Tile({
  label,
  onPress,
  compact,
  children,
}: {
  label: string;
  onPress?: () => void;
  compact?: boolean;
  children: ReactNode;
}) {
  const theme = useTheme();
  const content = (
    <>
      {children}
      <Text style={[styles.tileLabel, { color: theme.secondaryText }]} numberOfLines={2}>
        {label}
      </Text>
    </>
  );
  const style = compact ? styles.compactTile : styles.tile;
  return onPress ? (
    <Pressable
      accessibilityRole="button"
      accessibilityHint="Opens the image detail"
      onPress={onPress}
      style={({ pressed }) => [style, { opacity: pressed ? 0.7 : 1 }]}
    >
      {content}
    </Pressable>
  ) : (
    <View style={style}>{content}</View>
  );
}

function DecodedSizeTile({
  label,
  source,
  onPress,
}: {
  label: string;
  source: Source;
  onPress: () => void;
}) {
  const theme = useTheme();
  const [decoded, setDecoded] = useState<string>('loading…');
  return (
    <Tile label={`${label} → decoded ${decoded}`} onPress={onPress}>
      <TurboImage
        style={[styles.image, { backgroundColor: theme.imageBackground }]}
        source={source}
        resizeMode="cover"
        onSuccess={({ nativeEvent: { width, height } }) => setDecoded(`${width}×${height}`)}
        onFailure={({ nativeEvent: { code } }) => setDecoded(`failed (${code})`)}
      />
    </Tile>
  );
}

// The pattern that replaces 1.x's deprecated `indicator` prop.
function LoadingImage({
  source,
  style,
  placeholder,
}: {
  source: Source;
  style: StyleProp<ViewStyle>;
  placeholder?: string;
}) {
  const theme = useTheme();
  const [state, setState] = useState<'idle' | 'loading' | 'loaded' | { failed: string }>('idle');
  return (
    <View>
      <TurboImage
        style={style}
        source={source}
        resizeMode="cover"
        placeholder={placeholder ? { blurhash: placeholder } : undefined}
        showPlaceholderOnFailure={placeholder !== undefined}
        onStart={() => setState('loading')}
        onSuccess={() => setState('loaded')}
        onFailure={({ nativeEvent: { code } }) => setState({ failed: code })}
        // A cancelled load (source changed) is followed by a new onStart.
        onCompletion={({ nativeEvent }) =>
          setState((current) =>
            nativeEvent.state === 'cancelled' && current === 'loading' ? 'idle' : current
          )
        }
      />
      {state === 'loading' && (
        <ActivityIndicator style={StyleSheet.absoluteFill} color={theme.secondaryText} />
      )}
      {typeof state === 'object' && (
        <View style={[StyleSheet.absoluteFill, styles.failure]} pointerEvents="none">
          <Text style={[styles.failureText, { color: theme.danger }]}>
            Couldn’t load{'\n'}
            <Text style={styles.failureCode}>'{state.failed}'</Text>
          </Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: 12 },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  tile: { flex: 1, gap: 6 },
  // Three per row in the grid (3 × 31% + two 8 pt gaps fit a phone's card).
  compactTile: { width: '31%', gap: 6 },
  tileLabel: { fontSize: 12 },
  image: { width: '100%', aspectRatio: 3 / 2, borderRadius: 6 },
  square: { aspectRatio: 1 },
  failure: { alignItems: 'center', justifyContent: 'center' },
  failureText: { fontSize: 12, textAlign: 'center', fontWeight: '500' },
  failureCode: { fontWeight: '400' },
});
