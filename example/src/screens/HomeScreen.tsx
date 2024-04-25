import {
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
  FlatList,
} from 'react-native';
import React from 'react';
import { useNavigation } from '@react-navigation/native';
import {
  RouteName,
  type HomeStackNavigationProps,
  type HomeStackParamList,
} from './routes.type';
import TurboImage from '../../../src';

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

const ButtonItem = ({
  title,
  handlePress,
}: {
  title: string;
  handlePress: () => void;
}) => {
  return (
    <TouchableOpacity style={styles.button} onPress={handlePress}>
      <Text style={styles.buttonTitle}>{title}</Text>
    </TouchableOpacity>
  );
};
const routes = [
  { name: 'Grid', destination: RouteName.Grid },
  { name: 'Cache', destination: RouteName.Cache },
  { name: 'Image Processing', destination: RouteName.ImageProcessing },
];

const HomeScreen = () => {
  const handleClearMemoryCache = async () => {
    return await TurboImage.clearMemoryCache();
  };
  const handleClearDiskCache = async () => {
    return await TurboImage.clearDiskCache();
  };
  return (
    <View style={styles.container}>
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
      <View style={styles.butttonGroup}>
        <ButtonItem
          title="Clear Memory Cache"
          handlePress={handleClearMemoryCache}
        />
        <ButtonItem
          title="Clear Disk Cache"
          handlePress={handleClearDiskCache}
        />
      </View>
    </View>
  );
};

export default HomeScreen;

const styles = StyleSheet.create({
  container: {
    height: '100%',
  },
  itemTitle: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    fontSize: 26,
    fontWeight: 'bold',
  },
  butttonGroup: {
    bottom: 30,
  },
  buttonTitle: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    fontSize: 20,
    fontWeight: 'bold',
    color: 'white',
  },
  button: {
    backgroundColor: '#f54338',
    padding: 5,
    borderRadius: 5,
    margin: 5,
  },
});
