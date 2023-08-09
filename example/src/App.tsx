import React from 'react';
import { ScrollView, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';

export default function App() {
  const image = { source: 'https://placedog.net/300/200?id=12' };
  const images = Array(100).fill(image);
  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.contentContainer}
    >
      {images.map((img, idx) => (
        <TurboImage
          key={idx}
          source={img.source}
          style={styles.box}
          width={300}
          height={200}
        />
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
    height: 300,
    marginVertical: 20,
    backgroundColor: 'green',
  },
});
