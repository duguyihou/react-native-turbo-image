import React from 'react';
import { liveTextData } from '../data';
import Card from '../components/Card';
import { FlatList } from 'react-native';

const LiveTextScreen = () => {
  return (
    <FlatList
      data={liveTextData}
      renderItem={({ item }) => (
        <Card
          size={[300, 100]}
          source={{
            uri: item.url,
          }}
          indicator={{ style: 'large' }}
          enableLiveTextInteraction
        />
      )}
      keyExtractor={(item) => item.url}
    />
  );
};

export default LiveTextScreen;
