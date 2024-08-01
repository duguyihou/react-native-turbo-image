import React from 'react';
import { prefetchData } from '../data';
import Card from '../components/Card';
import { FlatList } from 'react-native';

const PrefetchScreen = () => {
  return (
    <FlatList
      data={prefetchData}
      renderItem={({ item }) => (
        <Card
          style={{ width: 300, height: 300 }}
          source={item}
          indicator={{ style: 'large' }}
        />
      )}
      keyExtractor={(item) => item.uri}
    />
  );
};

export default PrefetchScreen;
