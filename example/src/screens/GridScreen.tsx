import { Dimensions, FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import { blurhashString } from '../mockData';

const size = Dimensions.get('window').width / 3 - 2;
const GridScreen = () => {
  const imageURLs = Array.from(
    { length: 120 },
    (_, i) => `https://placedog.net/300/300?id=${i + 1}`
  );
  const renderItem = ({ item }: { item: string }) => {
    return (
      <TurboImage
        url={item}
        style={styles.card}
        showActivityIndicator
        blurhash={blurhashString}
        cachePolicy="dataCache"
      />
    );
  };
  return (
    <FlatList
      keyExtractor={(item) => item}
      data={imageURLs}
      numColumns={3}
      getItemLayout={(_, index) => ({
        length: size,
        offset: size * index,
        index,
      })}
      renderItem={renderItem}
    />
  );
};

export default GridScreen;

const styles = StyleSheet.create({
  card: {
    width: size,
    height: size,
    margin: 1,
  },
});
