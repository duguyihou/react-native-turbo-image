import { View, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';

const CacheScreen = () => {
  const imgUrl = 'http://localhost:3000/101.jpeg';
  return (
    <View style={styles.container}>
      <TurboImage url={imgUrl} style={styles.box} cachePolicy="memory" />
    </View>
  );
};

export default CacheScreen;

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
