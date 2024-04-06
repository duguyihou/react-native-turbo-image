import { Dimensions, FlatList, StyleSheet, Text, View } from 'react-native';
import React from 'react';
import TurboImage from '../../../src';

type Props = {
  title: string;
  url: string;
  priority: number;
};
const Card = ({ title, url, priority }: Props) => {
  return (
    <View style={styles.card}>
      <TurboImage url={url} style={styles.image} priority={priority} />
      <Text style={styles.title}>{title}</Text>
    </View>
  );
};

const images = [
  {
    title: 'verylow',
    url: 'https://placedog.net/300/300?id=230',
    priority: 0,
  },
  {
    title: 'low',
    url: 'https://placedog.net/300/300?id=231',
    priority: 1,
  },
  {
    title: 'normal',
    url: 'https://placedog.net/300/300?id=232',
    priority: 2,
  },
  {
    title: 'high',
    url: 'https://placedog.net/300/300?id=233',
    priority: 3,
  },

  {
    title: 'veryhigh',
    url: 'https://placedog.net/300/300?id=234',
    priority: 4,
  },
];
const size = Dimensions.get('window').width / 2 - 2;
const PriorityScreen = () => {
  return (
    <FlatList
      data={images}
      numColumns={2}
      renderItem={({ item }) => (
        <Card title={item.title} url={item.url} priority={item.priority} />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default PriorityScreen;

const styles = StyleSheet.create({
  card: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 20,
  },
  image: {
    width: size,
    height: size,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
  },
});
