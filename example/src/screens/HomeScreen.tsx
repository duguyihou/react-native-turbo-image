import { View, StyleSheet } from 'react-native';
import React from 'react';
import TurboImage from '../../../src';

const HomeScreen = () => {
  const imgUrl = 'https://placedog.net/300/200?id=1';
  return (
    <View style={styles.container}>
      <TurboImage
        url={imgUrl}
        style={styles.box}
        cachePolicy="urlCache"
        rounded
      />
    </View>
  );
};

export default HomeScreen;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    marginVertical: 20,
    width: 300,
    height: 200,
  },
});
