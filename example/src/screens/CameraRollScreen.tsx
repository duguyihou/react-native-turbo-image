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
  const [isPermissionGranted, setIsPermissionGranted] = useState<
    boolean | undefined
  >(() =>
    Platform.select({
      android: undefined,
      ios: true,
    })
  );
  const [state, setState] = useState({
    photos: [] as PhotoIdentifier[],
    endCursor: 'M',
    hasNextPage: true,
    isLoading: false,
  });

  // Destructure only what's needed in the JSX
  const { photos } = state;

  const loadInitialPhotos = useCallback(async () => {
    if (state.isLoading) return;
    if (state.photos.length || state.hasNextPage === false) return;

    setState((prev) => ({ ...prev, isLoading: true }));

    const params: GetPhotosParams = {
      first: 100,
      assetType: 'Photos',
      include: [
        'filename',
        'fileSize',
        'location',
        'imageSize',
        'playableDuration',
      ],
    };

    try {
      const result = await CameraRoll.getPhotos(params);
      setState((prev) => ({
        ...prev,
        photos: result.edges,
        endCursor: result.page_info.end_cursor || prev.endCursor,
        hasNextPage: result.page_info.has_next_page,
        isLoading: false,
      }));
    } catch (error) {
      console.error('Error fetching initial photos:', error);
      setState((prev) => ({ ...prev, isLoading: false }));
    }
  }, [state]);

  const loadMorePhotos = useCallback(async () => {
    if (!state.hasNextPage || state.isLoading) return;

    setState((prev) => ({ ...prev, isLoading: true }));

    const params: GetPhotosParams = {
      first: 100,
      assetType: 'Photos',
      after: state.endCursor,
      include: [
        'filename',
        'fileSize',
        'location',
        'imageSize',
        'playableDuration',
      ],
    };

    try {
      const result = await CameraRoll.getPhotos(params);
      setState((prev) => ({
        ...prev,
        photos: [...prev.photos, ...result.edges],
        endCursor: result.page_info.end_cursor || prev.endCursor,
        hasNextPage: result.page_info.has_next_page,
        isLoading: false,
      }));
    } catch (error) {
      console.error('Error loading more photos:', error);
      setState((prev) => ({ ...prev, isLoading: false }));
    }
  }, [state]);

  const requestAndroidPermission = useCallback(async () => {
    try {
      const permission = PermissionsAndroid.PERMISSIONS.READ_MEDIA_IMAGES;

      if (!permission) {
        console.warn('READ_MEDIA_IMAGES permission not found on this device');
        setIsPermissionGranted(false);
        return false;
      }

      const hasPermission = await PermissionsAndroid.check(permission);

      if (hasPermission) {
        setIsPermissionGranted(true);
        return true;
      }

      const granted = await PermissionsAndroid.request(permission, {
        title: 'Photo Permission',
        message: 'App needs access to your photos',
        buttonNeutral: 'Ask Me Later',
        buttonNegative: 'Cancel',
        buttonPositive: 'OK',
      });

      const isGranted = granted === PermissionsAndroid.RESULTS.GRANTED;
      setIsPermissionGranted(isGranted);
      return isGranted;
    } catch (err) {
      console.warn('Error requesting permission:', err);
      setIsPermissionGranted(false);
      return false;
    }
  }, []);

  // Handle initial load based on permission state
  useEffect(() => {
    const loadPhotosIfPermitted = async () => {
      if (Platform.OS === 'android') {
        if (isPermissionGranted === undefined) {
          // Initial state, request permission
          await requestAndroidPermission();
        } else if (isPermissionGranted) {
          // Permission granted, load photos
          loadInitialPhotos();
        }
        // If permission denied, do nothing
      } else {
        // On iOS, we can load photos directly
        loadInitialPhotos();
      }
    };

    loadPhotosIfPermitted();
  }, [isPermissionGranted, requestAndroidPermission, loadInitialPhotos]);

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
        onEndReached={loadMorePhotos}
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
