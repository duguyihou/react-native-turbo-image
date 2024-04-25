import { FlatList, Dimensions } from 'react-native';
import React from 'react';
import Card from '../components/Card';
import { imageProcessingData } from '../mockData';

const size = Dimensions.get('window').width / 2 - 2;

const ImageProcessingScreen = () => {
  return (
    <FlatList
      data={imageProcessingData}
      numColumns={2}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          src={item.url}
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
