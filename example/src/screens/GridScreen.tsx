import { Dimensions, FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import { gridScreenData } from '../mockData';

const size = Dimensions.get('window').width / 3 - 2;
const GridScreen = () => {
  const renderItem = ({
    item,
  }: {
    item: { url: string; blurhash: string };
  }) => {
    return (
      <TurboImage
        url={item.url}
        style={styles.card}
        showActivityIndicator
        blurhash={item.blurhash}
        cachePolicy="dataCache"
      />
    );
  };
  return (
    <FlatList
      keyExtractor={(item) => item.url}
      data={gridScreenData}
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
