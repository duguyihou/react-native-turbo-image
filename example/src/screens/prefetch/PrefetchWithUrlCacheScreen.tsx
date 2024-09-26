import React from 'react';
import { prefetchWithUrlCacheData } from './data';
import { FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const PrefetchWithUrlCacheScreen = () => {
  return (
    <FlatList
      data={prefetchWithUrlCacheData}
      renderItem={({ item }) => (
        <TurboImage
          style={styles.image}
          source={item}
          indicator={{ style: 'large' }}
          cachePolicy="urlCache"
        />
      )}
      keyExtractor={(item) => item.uri}
    />
  );
};

export default PrefetchWithUrlCacheScreen;

const styles = StyleSheet.create({
  image: {
    width: 360,
    height: 241,
  },
});
