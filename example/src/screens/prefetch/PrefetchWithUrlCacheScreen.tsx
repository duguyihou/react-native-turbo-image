import React from 'react';
import { prefetchWithUrlCacheData } from '../../data';
import Card from '../../components/Card';
import { FlatList, StyleSheet } from 'react-native';

const PrefetchWithUrlCacheScreen = () => {
  return (
    <FlatList
      data={prefetchWithUrlCacheData}
      renderItem={({ item }) => (
        <Card
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
    width: 300,
    height: 300,
  },
});
