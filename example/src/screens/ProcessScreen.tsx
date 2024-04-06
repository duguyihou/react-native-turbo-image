import { StyleSheet, Text, View, FlatList } from 'react-native';
import React from 'react';
import TurboImage from '../../../src';

type Process = 'rounded' | 'blur' | null;
type Props = {
  title: string;
  url: string;
  process: Process;
};
const Card = ({ title, url, process }: Props) => {
  return (
    <View style={styles.card}>
      <TurboImage
        url={url}
        style={styles.image}
        rounded={process === 'rounded'}
        blur={process === 'blur' ? 2 : undefined}
      />
      <Text style={styles.title}>{title}</Text>
    </View>
  );
};

const images = [
  {
    title: 'Original',
    url: 'https://placedog.net/300/300?id=238',
    process: null,
  },
  {
    title: 'Rounded',
    url: 'https://placedog.net/300/300?id=238',
    process: 'rounded',
  },
  {
    title: 'Blur',
    url: 'https://placedog.net/300/300?id=238',
    process: 'blur',
  },
];
const ProcessScreen = () => {
  return (
    <FlatList
      data={images}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          url={item.url}
          process={item.process as Process}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default ProcessScreen;

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  card: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 20,
  },
  image: {
    width: 300,
    height: 300,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
  },
});
