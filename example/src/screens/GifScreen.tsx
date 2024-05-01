import React from 'react';
import { gifData } from '../data';
import Card from '../components/Card';
import { FlatList } from 'react-native';

const GifScreen = () => {
  return (
    <FlatList
      data={gifData}
      renderItem={({ item }) => (
        <Card size={[300, 300]} src={item.url} showActivityIndicator />
      )}
      keyExtractor={(item) => item.url}
    />
  );
};

export default GifScreen;
