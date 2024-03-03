import { FlatList, StyleSheet, View } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import { blurhashString } from '../mockData';

const ListScreen = () => {
  const imageURLs = Array.from(
    { length: 100 },
    (_, i) => `https://placedog.net/300/200?id=${i + 1}`
  );
  return (
    <View style={styles.container}>
      <FlatList
        style={styles.list}
        contentContainerStyle={styles.listContent}
        keyExtractor={(item) => item}
        data={imageURLs}
        renderItem={({ item }) => {
          return (
            <TurboImage
              url={item}
              style={styles.box}
              showActivityIndicator
              blurhash={blurhashString}
              // base64Placeholder={base64Placeholder}
              // rounded
              cachePolicy="dataCache"
              // onSuccess={handleOnSuccess}
              // onError={handleOnError}
            />
          );
        }}
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
  title: {
    fontSize: 30,
    fontWeight: 'bold',
  },
  list: {
    width: '100%',
  },
  listContent: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    marginVertical: 20,
    width: 300,
    height: 200,
  },
});
