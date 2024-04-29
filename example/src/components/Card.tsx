import {
  StyleSheet,
  Text,
  View,
  type ColorValue,
  type NativeSyntheticEvent,
} from 'react-native';
import React from 'react';
import TurboImage, {
  type CachePolicy,
  type Failure,
  type Success,
  type Start,
} from 'react-native-turbo-image';

type Props = {
  size: number;
  title?: string;
  src: string;
  cachePolicy?: CachePolicy;
  priority?: number;
  rounded?: boolean;
  monochrome?: number | ColorValue;
  borderRadius?: number;
  blur?: number;
  blurhash?: string;
  resize?: number;
  showActivityIndicator?: boolean;
  onStart?: (result: NativeSyntheticEvent<Start>) => void;
  onSuccess?: (result: NativeSyntheticEvent<Success>) => void;
  onFailure?: (result: NativeSyntheticEvent<Failure>) => void;
};
const Card = ({ title, size, ...props }: Props) => {
  return (
    <View style={styles.card}>
      <TurboImage
        style={[styles.image, { width: size, height: size }]}
        {...props}
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
