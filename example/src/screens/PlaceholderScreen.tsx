import React from 'react';
import { placeholderData } from '../data';
import Card from '../components/Card';
import { FlatList } from 'react-native';

const PlaceholderScreen = () => {
  return (
    <FlatList
      data={placeholderData}
      renderItem={({ item }) => (
        <Card
          style={{ width: 300, height: 300 }}
          source={{
            uri: item.url,
          }}
          placeholder={item.placeholder}
          title={item.title}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default PlaceholderScreen;
