import {
  StyleSheet,
  Text,
  TouchableOpacity,
  Button,
  Alert,
  SectionList,
} from 'react-native';
import React, { useLayoutEffect } from 'react';
import { useNavigation } from '@react-navigation/native';
import {
  type HomeStackNavigationProps,
  type HomeStackParamList,
} from './routes.type';
import TurboImage from 'react-native-turbo-image';
import { prefetchData, routesData } from '../data';

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

const RightButton = () => {
  const handleClear = () => {
    Alert.alert('Clear Cache', 'memory / urlCache / dataCache', [
      {
        text: 'Prefetch',
        onPress: async () => {
          return await TurboImage.prefetch(prefetchData);
        },
        style: 'default',
      },
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
  return <Button title="Configuration" onPress={handleClear} />;
};

const HomeScreen = () => {
  const navigation = useNavigation<HomeStackNavigationProps>();
  useLayoutEffect(() =>
    navigation.setOptions({
      headerRight: RightButton,
    })
  );

  return (
    <SectionList
      sections={routesData}
      renderItem={({ item }) => (
        <ListItem
          name={item.name}
          destination={item.destination as keyof HomeStackParamList}
        />
      )}
      renderSectionHeader={({ section: { title } }) => {
        return <Text style={styles.header}>{title}</Text>;
      }}
      keyExtractor={(item, index) => item.name + index}
    />
  );
};

export default HomeScreen;

const styles = StyleSheet.create({
  header: {
    padding: 10,
    fontSize: 26,
    fontWeight: 'bold',
  },
  itemTitle: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    fontSize: 18,
  },
});
