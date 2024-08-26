import { Linking, Pressable, StyleSheet, Text, View } from 'react-native';
import React from 'react';
import TurboImage from 'react-native-turbo-image';
import { useRoute } from '@react-navigation/native';
import type { HomeRouteType, RouteName } from './routes.type';

const DetailScreen = () => {
  const {
    params: { memoryCacheKey },
  } = useRoute<HomeRouteType<RouteName.Detail>>();

  const handlePress = () => {
    Linking.openURL(
      'https://coil-kt.github.io/coil/recipes/#using-a-memory-cache-key-as-a-placeholder'
    );
  };
  return (
    <View style={styles.container}>
      <TurboImage
        source={{ uri: 'https://placedog.net/400/400?id=121' }}
        placeholder={{ memoryCacheKey }}
        style={styles.image}
      />
      <Text style={styles.text}>
        use the image which is cached in memory as placholder
      </Text>
      <Pressable onPress={handlePress}>
        <Text style={styles.link}>reference</Text>
      </Pressable>
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
  link: {
    fontSize: 18,
    color: 'blue',
  },
});
