import React from 'react';
import { gifData } from './data';
import { FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const GifScreen = () => {
  return (
    <FlatList
      data={gifData}
      renderItem={({ item }) => (
        <TurboImage
          style={styles.image}
          source={{ uri: item.uri }}
          indicator={{ style: 'large' }}
          format="gif"
        />
      )}
      keyExtractor={(item) => item.uri}
    />
  );
};

export default GifScreen;

const styles = StyleSheet.create({
  image: {
    width: 300,
    height: 300,
    alignSelf: 'center',
    marginBottom: 10,
  },
});
