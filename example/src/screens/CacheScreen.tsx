import { Dimensions, FlatList } from 'react-native';
import React from 'react';
import { type CachePolicy } from 'react-native-turbo-image';
import Card from '../components/Card';
import { cacheScreenData } from '../mockData';

const size = Dimensions.get('window').width / 2 - 2;

const CacheScreen = () => {
  return (
    <FlatList
      data={cacheScreenData}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          src={item.url}
          size={size}
          cachePolicy={item.cachePolicy as CachePolicy}
          blurhash={item.blurhash}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default CacheScreen;
