import React from 'react';
import { liveTextData } from '../data';
import { FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const LiveTextScreen = () => {
  return (
    <FlatList
      data={liveTextData}
      renderItem={({ item }) => (
        <TurboImage
          style={styles.image}
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

const styles = StyleSheet.create({
  image: {
    width: 300,
    height: 100,
    alignSelf: 'center',
  },
});
