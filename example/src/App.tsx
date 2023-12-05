import React from 'react';
import { SafeAreaView, ScrollView, StyleSheet, Text } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import { base64Placeholder, blurhashString } from './mockData';

export default function App() {
  const imageURLs = Array.from(
    { length: 100 },
    (_, i) => `https://placedog.net/300/200?id=${i}`
  );
  const handleOnSuccess = () => {};
  const handleOnError = (error: any) => {
    console.log(`🐵 ------ error`, error);
  };
  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        style={styles.container}
        contentContainerStyle={styles.contentContainer}
      >
        <Text style={styles.title}>Turbo Image Example</Text>
        {imageURLs.map((url, idx) => (
          <TurboImage
            key={idx}
            url={url}
            style={styles.box}
            resizeMode="stretch"
            showActivityIndicator
            // fadeDuration={10}
            blurhash={blurhashString}
            base64Placeholder={base64Placeholder}
            // rounded
            // tintColor="red"
            cachePolicy="memory"
            onSuccess={handleOnSuccess}
            onError={handleOnError}
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
  title: {
    fontSize: 30,
    fontWeight: 'bold',
  },
  box: {
    marginVertical: 20,
    width: 300,
    height: 200,
  },
});
