import { StyleSheet, Text, View, FlatList, Dimensions } from 'react-native';
import React from 'react';
import TurboImage from '../../../src';

type Processor = 'rounded' | 'blur' | 'monochrome' | 'borderRadius';
type Props = {
  title: string;
  url: string;
  processors: Processor[];
};
const Card = ({ title, url, processors }: Props) => {
  return (
    <View style={styles.card}>
      <TurboImage
        url={url}
        style={styles.image}
        rounded={processors.includes('rounded')}
        blur={processors.includes('blur') ? 5 : undefined}
        monochrome={processors.includes('monochrome') ? 'white' : undefined}
        borderRadius={processors.includes('borderRadius') ? 12 : undefined}
      />
      <Text style={styles.title}>{title}</Text>
    </View>
  );
};

const images = [
  {
    title: 'Original',
    url: 'https://placedog.net/300/300?id=238',
    processors: [],
  },
  {
    title: 'Monochrome',
    url: 'https://placedog.net/300/300?id=238',
    processors: ['monochrome'],
  },
  {
    title: 'Rounded Corners',
    url: 'https://placedog.net/300/300?id=238',
    processors: ['borderRadius'],
  },
  {
    title: 'Circle',
    url: 'https://placedog.net/300/300?id=238',
    processors: ['rounded'],
  },
  {
    title: 'Blur',
    url: 'https://placedog.net/300/300?id=238',
    processors: ['rounded', 'blur'],
  },
];
const size = Dimensions.get('window').width / 2 - 2;

const ImageProcessingScreen = () => {
  return (
    <FlatList
      data={images}
      numColumns={2}
      renderItem={({ item }) => (
        <Card
          title={item.title}
          url={item.url}
          processors={item.processors as Processor[]}
        />
      )}
      keyExtractor={(item) => item.title}
    />
  );
};

export default ImageProcessingScreen;

const styles = StyleSheet.create({
  card: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 20,
    margin: 1,
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
