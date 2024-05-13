import { StyleSheet, Text, View } from 'react-native';
import React from 'react';
import TurboImage, { type TurboImageProps } from 'react-native-turbo-image';

interface Props extends Omit<TurboImageProps, 'style'> {
  size: number;
  title?: string;
}
const Card = ({ title, size, ...props }: Props) => {
  return (
    <View style={styles.card}>
      <TurboImage
        {...props}
        style={[styles.image, { width: size, height: size }]}
      />
      {title && <Text style={styles.title}>{title}</Text>}
    </View>
  );
};

export default Card;

const styles = StyleSheet.create({
  card: {
    justifyContent: 'center',
    alignItems: 'center',
    paddingBottom: 20,
  },
  image: {
    margin: 1,
  },
  title: {
    fontSize: 16,
    fontWeight: 'bold',
  },
});
