import type { RouteProp } from '@react-navigation/native';
import type {
  NativeStackNavigationProp,
  NativeStackScreenProps,
} from '@react-navigation/native-stack';

export type HomeStackParamList = {
  Home: undefined;
  Cache: undefined;
  Grid: undefined;
  SuccessResult: undefined;
  FailureResult: undefined;
  ImageProcessing: undefined;
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
  Cache = 'Cache',
  Grid = 'Grid',
  SuccessResult = 'SuccessResult',
  FailureResult = 'FailureResult',
  ImageProcessing = 'ImageProcessing',
}
