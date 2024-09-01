import { Pressable, StyleSheet, Text, View } from 'react-native';
import React from 'react';
import { useNavigation } from '@react-navigation/native';
import { RouteName, type HomeStackNavigationProps } from '../routes.type';
import TurboImage from 'react-native-turbo-image';

const MemoryCacheKeyPreviousScreen = () => {
  const navigation = useNavigation<HomeStackNavigationProps>();

  const navigateToDetailScreen = () => {
    navigation.navigate(RouteName.MemoryCacheKey, {
      memoryCacheKey: 'https://placedog.net/100/100?id=127',
    });
  };
  return (
    <View style={styles.container}>
      <Pressable onPress={navigateToDetailScreen}>
        <TurboImage
          source={{
            uri: 'https://placedog.net/100/100?id=127',
          }}
          style={styles.image}
          cachePolicy="dataCache"
        />
      </Pressable>
      <Text style={styles.text}>
        The resolution of current image is 100 x 100. Click it and navigate to
        the next page
      </Text>
    </View>
  );
};

export default MemoryCacheKeyPreviousScreen;

const styles = StyleSheet.create({
  container: {
    height: '100%',
    width: '100%',
    alignItems: 'center',
  },
  image: {
    width: 100,
    height: 100,
  },

  text: {
    fontSize: 20,
    textAlign: 'center',
  },
});
