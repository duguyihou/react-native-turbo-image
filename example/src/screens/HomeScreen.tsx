import {
  StyleSheet,
  Text,
  TouchableOpacity,
  FlatList,
  Button,
  Alert,
} from 'react-native';
import React, { useLayoutEffect } from 'react';
import { useNavigation } from '@react-navigation/native';
import {
  RouteName,
  type HomeStackNavigationProps,
  type HomeStackParamList,
} from './routes.type';
import TurboImage from 'react-native-turbo-image';

const ListItem = ({
  name,
  destination,
}: {
  name: string;
  destination: keyof HomeStackParamList;
}) => {
  const navigation = useNavigation<HomeStackNavigationProps>();
  const handlePress = () => {
    navigation.push(destination);
  };
  return (
    <TouchableOpacity onPress={handlePress}>
      <Text style={styles.itemTitle}>{name}</Text>
    </TouchableOpacity>
  );
};

const routes = [
  { name: 'Grid', destination: RouteName.Grid },
  { name: 'Cache', destination: RouteName.Cache },
  { name: 'Image Processing', destination: RouteName.ImageProcessing },
];

const RightButton = () => {
  const handleClear = () => {
    Alert.alert('Clear Cache', 'memory / urlCache / dataCache', [
      {
        text: 'Clear Memory Cache',
        onPress: async () => {
          return await TurboImage.clearMemoryCache();
        },
      },
      {
        text: 'Clear Disk Cache',
        onPress: async () => {
          return await TurboImage.clearDiskCache();
        },
      },
      {
        text: 'Cancel',
        style: 'cancel',
      },
    ]);
  };
  return <Button title="Clear" onPress={handleClear} />;
};

const HomeScreen = () => {
  const navigation = useNavigation<HomeStackNavigationProps>();
  useLayoutEffect(() =>
    navigation.setOptions({
      headerRight: RightButton,
    })
  );

  return (
    <FlatList
      data={routes}
      renderItem={({ item }) => (
        <ListItem
          name={item.name}
          destination={item.destination as keyof HomeStackParamList}
        />
      )}
      keyExtractor={(item) => item.name}
    />
  );
};

export default HomeScreen;

const styles = StyleSheet.create({
  itemTitle: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    fontSize: 26,
    fontWeight: 'bold',
  },
});
