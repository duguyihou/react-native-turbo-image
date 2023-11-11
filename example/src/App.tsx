import React from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Text } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import images from './mockData';

export default function App() {
  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.contentContainer}
      >
        <Text>Turbo Image</Text>
        {images.map((img, idx) => (
          <TurboImage
            key={idx}
            url={img.url}
            style={styles.box}
            resizeMode="center"
          />
        ))}
      </ScrollView>
    </SafeAreaView>
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
    marginVertical: 20,
    width: 300,
    height: 200,
    backgroundColor: 'blue',
  },
});
