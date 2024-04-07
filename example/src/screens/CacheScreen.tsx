import { Dimensions, FlatList } from 'react-native';
import React from 'react';
import { type CachePolicy } from 'react-native-turbo-image';
import Card from '../components/Card';

const images = [
  {
    title: 'memory',
    url: 'https://placedog.net/300/300?id=235',
    cachePolicy: 'memory',
  },
  {
    title: 'dataCache',
    url: 'https://placedog.net/300/300?id=236',
    cachePolicy: 'dataCache',
  },
  {
    title: 'urlCache',
    url: 'http://localhost:3000/237.jpeg',
    cachePolicy: 'urlCache',
  },
];

const size = Dimensions.get('window').width / 2 - 2;

const CacheScreen = () => {
  return (
    <FlatList
      data={images}
      numColumns={2}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          url={item.url}
          size={size}
          cachePolicy={item.cachePolicy as CachePolicy}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default CacheScreen;
