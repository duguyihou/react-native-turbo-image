import React from 'react';
import { ScrollView, StyleSheet, Text } from 'react-native';
import TurboImage from 'react-native-turbo-image';

export default function App() {
  const images = [
    {
      source: {
        uri: 'https://placedog.net/300/200?id=1',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=2',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=3',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=4',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=5',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=6',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=7',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=8',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=9',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=10',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=11',
      },
    },
    {
      source: {
        uri: 'https://placedog.net/300/200?id=12',
      },
    },
  ];
  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.contentContainer}
    >
      <Text>Turbo Image</Text>
      {images.map((img, idx) => (
        <TurboImage
          key={idx}
          source={img.source}
          style={styles.box}
          width={300}
          height={200}
          resizeMode="center"
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
    marginVertical: 20,
  },
});
