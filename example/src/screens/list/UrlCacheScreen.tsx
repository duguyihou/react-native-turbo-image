import { Dimensions, FlatList, StyleSheet } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import { urlCacheListData } from '../../data';

const size = Dimensions.get('window').width / 3 - 2;
const UrlCacheScreen = () => {
  const renderItem = ({ item }: { item: { uri: string } }) => {
    return (
      <TurboImage
        source={{
          uri: item.uri,
        }}
        style={styles.card}
        resizeMode="cover"
      />
    );
  };
  return (
    <FlatList
      keyExtractor={(item) => item.uri}
      data={urlCacheListData}
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

export default UrlCacheScreen;

const styles = StyleSheet.create({
  card: {
    width: size,
    height: size,
    margin: 1,
    borderRadius: 20,
  },
});
