import { Dimensions, FlatList, StyleSheet, View } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import { blurhashString } from '../mockData';

const size = Dimensions.get('window').width / 3;
const ListScreen = () => {
  const imageURLs = Array.from(
    { length: 236 },
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
        borderRadius={8}
      />
    );
  };
  return (
    <View style={styles.container}>
      <FlatList
        style={styles.list}
        columnWrapperStyle={styles.listContent}
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
    </View>
  );
};

export default ListScreen;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  list: {
    width: '100%',
    height: '100%',
  },
  listContent: {
    alignItems: 'center',
    justifyContent: 'space-between',
    width: '100%',
  },
  card: {
    width: size,
    height: size,
  },
});
