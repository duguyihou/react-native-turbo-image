import { Platform, StyleSheet, Text, View } from 'react-native';
import { TurboImage } from 'react-native-turbo-image';
import type { Navigate } from '../../App';
import { BLURHASH, photoUrl } from '../fixtures';
import { ServerBanner } from '../ServerBanner';
import { useTheme } from '../theme';
import { Caption, Code, NavRow, Screen, Section } from '../ui';

const QUICK_START = `import { TurboImage } from 'react-native-turbo-image';

<TurboImage
  source={{ uri: 'https://example.com/photo.jpg' }}
  style={{ width: '100%', aspectRatio: 3 / 2 }}
  resizeMode="cover"
  placeholder={{ blurhash: '${BLURHASH}' }}
/>`;

export function HomeScreen({
  navigate,
  cacheConfigured,
}: {
  navigate: Navigate;
  cacheConfigured: boolean;
}) {
  const theme = useTheme();
  const { major, minor, patch } = Platform.constants.reactNativeVersion;
  return (
    <Screen title="TurboImage">
      <ServerBanner always />
      <View style={styles.hero}>
        <TurboImage
          style={styles.heroImage}
          source={{ uri: photoUrl('home') }}
          placeholder={{ blurhash: BLURHASH }}
          // Without the server, keep the blurhash rather than an empty box.
          showPlaceholderOnFailure
          resizeMode="cover"
        />
        <Text style={[styles.lead, { color: theme.text }]}>
          A fast image component for React Native's New Architecture, backed by Nuke on iOS and Coil
          on Android.
        </Text>
      </View>

      <Section title="Quick start">
        <Code>{QUICK_START}</Code>
        <Caption>
          resizeMode defaults to "contain" (as in TurboImage 1.x; React Native's Image uses
          "cover").
        </Caption>
      </Section>

      <Section title="Demos">
        <NavRow
          title="Gallery"
          subtitle="Remote and local images, sizes, resize modes, placeholders, corners, loading and error states"
          onPress={() => navigate({ name: 'gallery' })}
        />
        <NavRow
          title="Image detail"
          subtitle="One image with its event log: headers, cache policies, transformations, animated formats, errors"
          onPress={() => navigate({ name: 'detail' })}
        />
        <NavRow
          title="Performance"
          subtitle="100 to 1000 images, fast scrolling, repeated URLs, remounting, offline recovery"
          onPress={() => navigate({ name: 'performance' })}
        />
        <NavRow
          title="Playground"
          subtitle="Every public prop, with the JSX to copy"
          onPress={() => navigate({ name: 'playground' })}
        />
      </Section>

      <Section title="For maintainers">
        <NavRow
          title="Smoke test"
          subtitle="The suite scripts/smoke-*.sh runs on a fresh install. Run here, caches are warm."
          onPress={() => navigate({ name: 'smoke' })}
        />
        <Caption>
          {`React Native ${major}.${minor}.${patch} · ${Platform.OS} ${Platform.Version} · ${
            __DEV__ ? 'debug' : 'release'
          } build · caches configured at startup: ${cacheConfigured ? 'yes' : 'no'}`}
        </Caption>
      </Section>
    </Screen>
  );
}

const styles = StyleSheet.create({
  hero: { gap: 12 },
  heroImage: { width: '100%', aspectRatio: 3 / 2, borderRadius: 12 },
  lead: { fontSize: 15, lineHeight: 21 },
});
