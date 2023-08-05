import React from 'react';
import { ScrollView, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';

export default function App() {
  const image = { source: 'https://picsum.photos/seed/picsum/200/300' };
  const images = Array(100).fill(image);
  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.contentContainer}
    >
      {images.map((img, idx) => (
        <TurboImage key={idx} source={img.source} style={styles.box} />
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  contentContainer: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    width: 300,
    height: 200,
    marginVertical: 20,
  },
});
