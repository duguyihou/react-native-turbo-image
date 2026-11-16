// Minimal TurboImage 2.0 example: one Fabric <TurboImage> per cache policy.
//
// Its job is to prove the toolchain end to end (Codegen → Fabric view →
// shared C++ core → Nuke/Coil adapter) on both platforms, not to show off
// features. The image pipeline milestone builds on top of this.
import { useState } from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Text, View } from 'react-native';
import { TurboImage } from 'react-native-turbo-image';
import type { TurboImageProps } from 'react-native-turbo-image';

const IMAGE_URI = 'https://picsum.photos/id/1025/600/400';

const POLICIES: NonNullable<TurboImageProps['cachePolicy']>[] = [
  'default',
  'memoryOnly',
  'noCache',
  'cacheOnly',
];

function PolicyCard({ policy }: { policy: (typeof POLICIES)[number] }) {
  const [status, setStatus] = useState('loading…');
  return (
    <View style={styles.card}>
      <Text style={styles.label}>
        cachePolicy="{policy}" · {status}
      </Text>
      <TurboImage
        testID={`image-${policy}`}
        style={styles.image}
        source={{ uri: IMAGE_URI }}
        cachePolicy={policy}
        resizeMode="cover"
        onLoad={(e) =>
          setStatus(`loaded ${e.nativeEvent.width}×${e.nativeEvent.height}`)
        }
        onError={(e) => setStatus(`error: ${e.nativeEvent.message}`)}
      />
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaView style={styles.root}>
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.title}>TurboImage 2.0 walking skeleton</Text>
        {POLICIES.map((policy) => (
          <PolicyCard key={policy} policy={policy} />
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: { padding: 16, gap: 16 },
  title: { fontSize: 20, fontWeight: '600' },
  card: { gap: 8 },
  label: { fontSize: 13, fontFamily: 'Menlo' },
  image: { width: '100%', aspectRatio: 3 / 2, backgroundColor: '#ddd' },
});
