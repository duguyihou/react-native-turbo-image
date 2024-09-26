import React from 'react';
import { apngData } from './data';
import { FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const APNGScreen = () => {
  return (
    <FlatList
      data={apngData}
      renderItem={({ item }) => (
        <TurboImage
          style={styles.image}
          source={{ uri: item.uri }}
          indicator={{ style: 'large' }}
          format="apng"
        />
      )}
      keyExtractor={(item) => item.uri}
    />
  );
};

export default APNGScreen;

const styles = StyleSheet.create({
  image: {
    width: 300,
    height: 300,
    alignSelf: 'center',
  },
});
