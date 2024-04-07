import { FlatList, Dimensions } from 'react-native';
import React from 'react';
import Card from '../components/Card';

const images = [
  {
    title: 'Original',
    url: 'https://placedog.net/300/300?id=238',
  },
  {
    title: 'Rounded Corners',
    url: 'https://placedog.net/300/300?id=238',
    borderRadius: 12,
  },
  {
    title: 'Monochrome',
    url: 'https://placedog.net/300/300?id=238',
    monochrome: 'white',
    borderRadius: 12,
  },
  {
    title: 'Circle',
    url: 'https://placedog.net/300/300?id=238',
    rounded: true,
  },
  {
    title: 'Blur',
    url: 'https://placedog.net/300/300?id=238',
    blur: 5,
    rounded: true,
  },
];
const size = Dimensions.get('window').width / 2 - 2;

const ImageProcessingScreen = () => {
  return (
    <FlatList
      data={images}
      numColumns={2}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          url={item.url}
          size={size}
          rounded={item.rounded}
          blur={item.blur}
          monochrome={item.monochrome}
          borderRadius={item.borderRadius}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default ImageProcessingScreen;
