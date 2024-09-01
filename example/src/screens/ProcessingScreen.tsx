import { FlatList, Dimensions, StyleSheet } from 'react-native';
import React from 'react';
import Card from '../components/Card';
import { processingData } from '../data';

const size = Dimensions.get('window').width / 2 - 2;

const ProcessingScreen = () => {
  return (
    <FlatList
      contentContainerStyle={styles.container}
      data={processingData}
      numColumns={2}
      renderItem={({ item: { url, resize, ...props } }) => (
        <Card
          {...props}
          source={{
            uri: url,
          }}
          style={{ width: resize ?? size, height: resize ?? size }}
          indicator={{
            style: 'large',
            color: 'red',
          }}
          cachePolicy="dataCache"
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default ProcessingScreen;

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
  },
});
