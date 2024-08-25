import { StyleSheet, Text, View } from 'react-native';
import React from 'react';
import TurboImage from 'react-native-turbo-image';
import { useRoute } from '@react-navigation/native';
import type { HomeRouteType, RouteName } from './routes.type';

const DetailScreen = () => {
  const {
    params: { memoryCacheKey },
  } = useRoute<HomeRouteType<RouteName.Detail>>();
  return (
    <View style={styles.container}>
      <TurboImage
        source={{ uri: 'https://placedog.net/400/400?id=121' }}
        placeholder={{ memoryCacheKey }}
        style={styles.image}
      />
      <Text style={styles.text}>
        reference to
        https://coil-kt.github.io/coil/recipes/#using-a-memory-cache-key-as-a-placeholder
      </Text>
    </View>
  );
};

export default DetailScreen;

const styles = StyleSheet.create({
  container: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  image: {
    width: 400,
    height: 400,
  },
  text: {
    fontSize: 18,
  },
});
