import React from 'react';
import { StyleSheet, View } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const BlurhashScreen = () => {
  return (
    <View style={styles.container}>
      <TurboImage
        style={styles.image}
        source={{
          uri: 'https://placedog.net/300/300?id=127',
        }}
        cachePolicy="dataCache"
        placeholder={{
          blurhash: 'KBHKzp00_N_19F-V00_2D%',
        }}
      />
    </View>
  );
};

export default BlurhashScreen;

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  image: {
    width: 300,
    height: 300,
  },
});
