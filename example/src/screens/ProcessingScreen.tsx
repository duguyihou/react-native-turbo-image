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
      renderItem={({ item }) => (
        <Card
          title={item.title}
          src={item.url}
          size={item.resize ?? [size, size]}
          rounded={item.rounded}
          blur={item.blur}
          monochrome={item.monochrome}
          resize={item.resize}
          indicator="large"
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
