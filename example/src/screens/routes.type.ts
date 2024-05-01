import type { RouteProp } from '@react-navigation/native';
import type {
  NativeStackNavigationProp,
  NativeStackScreenProps,
} from '@react-navigation/native-stack';

export type HomeStackParamList = {
  Home: undefined;
  TurboImage: undefined;
  Image: undefined;
  MemoryCache: undefined;
  UrlCache: undefined;
  DataCache: undefined;
  Success: undefined;
  Failure: undefined;
  ImageProcessing: undefined;
  SVG: undefined;
  Gif: undefined;
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
  TurboImage = 'TurboImage',
  Image = 'Image',
  MemoryCache = 'MemoryCache',
  UrlCache = 'UrlCache',
  DataCache = 'DataCache',
  Success = 'Success',
  Failure = 'Failure',
  ImageProcessing = 'ImageProcessing',
  SVG = 'SVG',
  Gif = 'Gif',
}
