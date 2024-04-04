import { StyleSheet, Text, ScrollView } from 'react-native';
import React from 'react';
import TurboImage from '../../../src';

const ProcessScreen = () => {
  const imgUrl = 'https://placedog.net/300/300?id=238';
  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>Original</Text>
      <TurboImage url={imgUrl} style={styles.card} showActivityIndicator />
      <Text style={styles.title}>Rounded</Text>
      <TurboImage
        url={imgUrl}
        style={styles.card}
        // showActivityIndicator
        rounded
      />
      <Text style={styles.title}>Blur</Text>
      <TurboImage url={imgUrl} style={styles.card} showActivityIndicator blur />
    </ScrollView>
  );
};

export default ProcessScreen;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  card: {
    width: 300,
    height: 300,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
  },
});
