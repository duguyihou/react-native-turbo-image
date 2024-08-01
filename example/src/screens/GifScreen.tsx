import React from 'react';
import { gifData } from '../data';
import Card from '../components/Card';
import { FlatList } from 'react-native';

const GifScreen = () => {
  return (
    <FlatList
      data={gifData}
      renderItem={({ item }) => (
        <Card
          style={{ width: 300, height: 300 }}
          source={{
            uri: item.url,
          }}
          indicator={{ style: 'large' }}
          format="gif"
        />
      )}
      keyExtractor={(item) => item.url}
    />
  );
};

export default GifScreen;
