import React from 'react';
import { PrefetchWithDataCacheData } from './data';
import { FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const PrefetchWithDataCacheScreen = () => {
  return (
    <FlatList
      data={PrefetchWithDataCacheData}
      renderItem={({ item }) => (
        <TurboImage
          style={styles.image}
          source={item}
          indicator={{ style: 'large' }}
          cachePolicy="dataCache"
        />
      )}
      keyExtractor={(item) => item.uri}
    />
  );
};

export default PrefetchWithDataCacheScreen;

const styles = StyleSheet.create({
  image: {
    width: 300,
    height: 300,
    alignSelf: 'center',
    marginBottom: 10,
  },
});
