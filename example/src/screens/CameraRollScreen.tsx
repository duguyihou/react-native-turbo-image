import React from 'react';
import { useCallback } from 'react';
import { useState, useEffect } from 'react';
import {
  View,
  StyleSheet,
  FlatList,
  PermissionsAndroid,
  Platform,
  Text,
} from 'react-native';
import type { ListRenderItem } from 'react-native';
import { CameraRoll } from '@react-native-camera-roll/camera-roll';
import type {
  PhotoIdentifier,
  GetPhotosParams,
} from '@react-native-camera-roll/camera-roll';
import TurboImage from 'react-native-turbo-image';

const CameraRollScreen: React.FC = () => {
  const [photos, setPhotos] = useState<PhotoIdentifier[]>([]);
  const [endCursor, setEndCursor] = useState<string>('M');
  const [hasNextPage, setHasNextPage] = useState<boolean>(true);
  const [isLoading, setIsLoading] = useState<boolean>(false);

  const loadPhotos = useCallback(async () => {
    if (!hasNextPage || isLoading) return;

    try {
      setIsLoading(true);
      const params: GetPhotosParams = {
        first: 100,
        assetType: 'Photos',
      };

      if (endCursor !== 'M') {
        params.after = endCursor;
      }

      const result = await CameraRoll.getPhotos(params);

      setPhotos((prevPhotos) => [...prevPhotos, ...result.edges]);
      if (result.page_info.end_cursor) {
        setEndCursor(result.page_info.end_cursor);
      }
      setHasNextPage(result.page_info.has_next_page);
    } catch (error) {
      console.error('Error fetching photos:', error);
    } finally {
      setIsLoading(false);
    }
  }, [endCursor, hasNextPage, isLoading]);

  const requestAndroidPermission = useCallback(async () => {
    try {
      const permission = PermissionsAndroid.PERMISSIONS.READ_MEDIA_IMAGES;
      if (!permission) {
        console.warn('READ_MEDIA_IMAGES permission not found');
        return;
      }

      const granted = await PermissionsAndroid.request(permission, {
        title: 'Photo Permission',
        message: 'App needs access to your photos',
        buttonNeutral: 'Ask Me Later',
        buttonNegative: 'Cancel',
        buttonPositive: 'OK',
      });

      if (granted === PermissionsAndroid.RESULTS.GRANTED) {
        loadPhotos();
      }
    } catch (err) {
      console.warn('Error requesting permission:', err);
    }
  }, [loadPhotos]);

  useEffect(() => {
    if (Platform.OS === 'android') {
      requestAndroidPermission();
    } else {
      loadPhotos();
    }
  }, [requestAndroidPermission, loadPhotos]);

  const renderItem: ListRenderItem<PhotoIdentifier> = ({ item }) => (
    <TurboImage
      source={{ uri: item.node.image.uri, size: { width: 490, height: 490 } }}
      style={styles.image}
      resizeMode="cover"
    />
  );

  return (
    <View style={styles.container}>
      <FlatList
        data={photos}
        renderItem={renderItem}
        keyExtractor={(_, index) => index.toString()}
        numColumns={3}
        onEndReached={loadPhotos}
        onEndReachedThreshold={0.5}
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Text>No photos found</Text>
          </View>
        }
      />
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
  },
  image: {
    width: '33.33%',
    aspectRatio: 1,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
});

export default CameraRollScreen;
