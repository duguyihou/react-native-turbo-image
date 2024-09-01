import React from 'react';
import { PrefetchWithDataCacheData } from '../../data';
import Card from '../../components/Card';
import { FlatList, StyleSheet } from 'react-native';

const PrefetchWithDataCacheScreen = () => {
  return (
    <FlatList
      data={PrefetchWithDataCacheData}
      renderItem={({ item }) => (
        <Card
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
  },
});
