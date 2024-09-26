import { Dimensions, FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import { dataCachelistData } from './data';

const size = Dimensions.get('window').width / 3 - 2;
const DataCacheScreen = () => {
  const renderItem = ({
    item,
  }: {
    item: { uri: string; blurhash: string };
  }) => {
    return (
      <TurboImage
        source={{
          uri: item.uri,
        }}
        style={styles.card}
        placeholder={{ blurhash: item.blurhash }}
        resize={size}
        cachePolicy="dataCache"
      />
    );
  };
  return (
    <FlatList
      keyExtractor={(item) => item.uri}
      data={dataCachelistData}
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

export default DataCacheScreen;

const styles = StyleSheet.create({
  card: {
    width: size,
    height: size,
    margin: 1,
    borderRadius: 20,
  },
});
