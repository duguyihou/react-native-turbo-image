import { Dimensions, FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import { listScreenData } from '../data';

const size = Dimensions.get('window').width / 3 - 2;
const TurboImageScreen = () => {
  const renderItem = ({
    item,
  }: {
    item: { url: string; blurhash: string };
  }) => {
    return (
      <TurboImage
        src={item.url}
        style={styles.card}
        indicator="large"
        blurhash={item.blurhash}
        resize={[size, size]}
      />
    );
  };
  return (
    <FlatList
      keyExtractor={(item) => item.url}
      data={listScreenData}
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

export default TurboImageScreen;

const styles = StyleSheet.create({
  card: {
    width: size,
    height: size,
    margin: 1,
  },
});
