import { FlatList } from 'react-native';
import React from 'react';
import { type CachePolicy } from 'react-native-turbo-image';
import Card from '../components/Card';

const images = [
  {
    title: 'shared',
    url: 'https://placedog.net/300/300?id=235',
    cachePolicy: 'dataCache',
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

const CacheScreen = () => {
  return (
    <FlatList
      data={images}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          url={item.url}
          size={200}
          cachePolicy={item.cachePolicy as CachePolicy}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default CacheScreen;
