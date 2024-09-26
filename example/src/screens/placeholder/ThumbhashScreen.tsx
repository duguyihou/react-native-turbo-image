import React from 'react';
import { StyleSheet, View } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const ThumbhashScreen = () => {
  return (
    <View style={styles.container}>
      <TurboImage
        style={styles.image}
        source={{
          uri: 'https://placedog.net/300/300?id=127',
        }}
        cachePolicy="dataCache"
        placeholder={{
          thumbhash: 'XDkKFwKgVndpiIikloh4Z4iGp/HMDKYI',
        }}
      />
      <TurboImage
        style={styles.image}
        source={{
          uri: 'https://placedog.net/300/300?id=127000',
        }}
        showPlaceholderOnFailure
        cachePolicy="dataCache"
        placeholder={{
          thumbhash: 'XDkKFwKgVndpiIikloh4Z4iGp/HMDKYI',
        }}
      />
    </View>
  );
};

export default ThumbhashScreen;

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  image: {
    width: 300,
    height: 300,
    marginBottom: 10,
  },
});
