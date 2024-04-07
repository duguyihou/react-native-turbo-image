import { Dimensions, FlatList } from 'react-native';
import React from 'react';
import Card from '../components/Card';

const images = [
  {
    title: 'verylow',
    url: 'https://placedog.net/300/300?id=230',
    priority: 0,
  },
  {
    title: 'low',
    url: 'https://placedog.net/300/300?id=231',
    priority: 1,
  },
  {
    title: 'normal',
    url: 'https://placedog.net/300/300?id=232',
    priority: 2,
  },
  {
    title: 'high',
    url: 'https://placedog.net/300/300?id=233',
    priority: 3,
  },
  {
    title: 'veryhigh',
    url: 'https://placedog.net/300/300?id=234',
    priority: 4,
  },
];
const size = Dimensions.get('window').width / 2 - 2;
const PriorityScreen = () => {
  return (
    <FlatList
      data={images}
      numColumns={2}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          url={item.url}
          priority={item.priority}
          size={size}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default PriorityScreen;
