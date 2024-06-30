import React from 'react';
import { gifData } from '../data';
import Card from '../components/Card';
import { FlatList } from 'react-native';
import type { Format } from 'react-native-turbo-image';

const GifScreen = () => {
  return (
    <FlatList
      data={gifData}
      renderItem={({ item }) => (
        <Card
          size={300}
          source={{
            uri: item.url,
          }}
          indicator={{ style: 'large' }}
          format={item.format as Format}
        />
      )}
      keyExtractor={(item) => item.url}
    />
  );
};

export default GifScreen;
