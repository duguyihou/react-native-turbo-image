import { View, StyleSheet, Text, FlatList } from 'react-native';
import TurboImage from 'react-native-turbo-image';
import React from 'react';
import type { CachePolicy } from '../../../src/types';

const images = [
  {
    title: 'shared',
    url: 'https://placedog.net/300/300?id=235',
    cachePolicy: 'dataCache',
  },
  {
    title: 'dataCache',
    url: 'https://placedog.net/300/300?id=236',
    cachePolicy: 'dataCache',
  },
  {
    title: 'urlCache',
    url: 'http://localhost:3000/237.jpeg',
    cachePolicy: 'urlCache',
  },
];

type Props = {
  title: string;
  url: string;
  cachePolicy: CachePolicy;
};
const Card = ({ title, url, cachePolicy }: Props) => {
  return (
    <View style={styles.card}>
      <TurboImage url={url} style={styles.image} cachePolicy={cachePolicy} />
      <Text style={styles.title}>{title}</Text>
    </View>
  );
};

const CacheScreen = () => {
  return (
    <FlatList
      data={images}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          url={item.url}
          cachePolicy={item.cachePolicy as CachePolicy}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default CacheScreen;

const styles = StyleSheet.create({
  card: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 20,
  },
  image: {
    width: 200,
    height: 200,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
  },
});
