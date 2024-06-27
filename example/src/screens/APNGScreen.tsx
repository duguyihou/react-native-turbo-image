import React from 'react';
import { apngData } from '../data';
import Card from '../components/Card';
import { FlatList } from 'react-native';

const APNGScreen = () => {
  return (
    <FlatList
      data={apngData}
      renderItem={({ item }) => (
        <Card
          size={300}
          src={item.url}
          indicator={{ style: 'large' }}
          isAPNG={item.isAPNG}
        />
      )}
      keyExtractor={(item) => item.url}
    />
  );
};

export default APNGScreen;
