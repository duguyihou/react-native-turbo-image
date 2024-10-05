import type { RouteProp } from '@react-navigation/native';
import type {
  NativeStackNavigationProp,
  NativeStackScreenProps,
} from '@react-navigation/native-stack';

export type HomeStackParamList = {
  Home: undefined;
  Image: undefined;
  DynamaticUri: undefined;
  Thumbhash: undefined;
  Blurhash: undefined;
  MemoryCacheKeyPrevious: undefined;
  MemoryCacheKey: { memoryCacheKey: string };
  UrlCache: undefined;
  DataCache: undefined;
  PrefetchWithUrlCache: undefined;
  PrefetchWithDataCache: undefined;
  Success: undefined;
  Failure: undefined;
  ImageProcessing: undefined;
  LiveText: undefined;
  SVG: undefined;
  Gif: undefined;
  APNG: undefined;
};

export type HomeStackProps = NativeStackScreenProps<HomeStackParamList>;
export type HomeStackNavigationProps =
  NativeStackNavigationProp<HomeStackParamList>;

export type HomeRouteType<K extends keyof HomeStackParamList> = RouteProp<
  HomeStackParamList,
  K
>;

export enum RouteName {
  HomeStack = 'HomeStack',
  Home = 'Home',
  Image = 'Image',
  DynamaticUri = 'DynamaticUri',
  Thumbhash = 'Thumbhash',
  Blurhash = 'Blurhash',
  MemoryCacheKeyPrevious = 'MemoryCacheKeyPrevious',
  MemoryCacheKey = 'MemoryCacheKey',
  UrlCache = 'UrlCache',
  DataCache = 'DataCache',
  PrefetchWithUrlCache = 'PrefetchWithUrlCache',
  PrefetchWithDataCache = 'PrefetchWithDataCache',
  Success = 'Success',
  Failure = 'Failure',
  ImageProcessing = 'ImageProcessing',
  LiveText = 'LiveText',
  SVG = 'SVG',
  Gif = 'Gif',
  APNG = 'APNG',
}
