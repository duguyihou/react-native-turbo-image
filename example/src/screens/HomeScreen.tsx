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
import { routesData } from '../data';
import {
  PrefetchWithDataCacheData,
  prefetchWithUrlCacheData,
} from './prefetch/data';

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

const LeftButton = () => {
  const handlePrefetch = () => {
    Alert.alert('prefetch', '', [
      {
        text: 'Prefetch with urlCache',
        onPress: async () => {
          return await TurboImage.prefetch(prefetchWithUrlCacheData);
        },
        style: 'default',
      },
      {
        text: 'Prefetch with dataCache',
        onPress: async () => {
          return await TurboImage.prefetch(
            PrefetchWithDataCacheData,
            'dataCache'
          );
        },
        style: 'default',
      },
      {
        text: 'Cancel',
        style: 'cancel',
      },
    ]);
  };
  return <Button title="Prefetch" onPress={handlePrefetch} />;
};

const RightButton = () => {
  const handleClear = () => {
    Alert.alert('Clear Cache', 'memory / disk', [
      {
        text: 'Clear Memory Cache',
        onPress: async () => {
          return await TurboImage.clearMemoryCache();
        },
        style: 'default',
      },
      {
        text: 'Clear Disk Cache',
        onPress: async () => {
          return await TurboImage.clearDiskCache();
        },
        style: 'default',
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
      headerLeft: LeftButton,
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
