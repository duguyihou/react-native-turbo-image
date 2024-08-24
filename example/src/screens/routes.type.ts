import type { RouteProp } from '@react-navigation/native';
import type {
  NativeStackNavigationProp,
  NativeStackScreenProps,
} from '@react-navigation/native-stack';

export type HomeStackParamList = {
  Home: undefined;
  Image: undefined;
  Placeholder: undefined;
  UrlCache: undefined;
  DataCache: undefined;
  Prefetch: undefined;
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
  Placeholder = 'Placeholder',
  UrlCache = 'UrlCache',
  DataCache = 'DataCache',
  Prefetch = 'Prefetch',
  Success = 'Success',
  Failure = 'Failure',
  ImageProcessing = 'ImageProcessing',
  LiveText = 'LiveText',
  SVG = 'SVG',
  Gif = 'Gif',
  APNG = 'APNG',
}
