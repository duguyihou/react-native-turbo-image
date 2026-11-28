/**
 * @format
 */

import { AppRegistry } from 'react-native';
import App from './App';
import { name as appName } from './app.json';

AppRegistry.registerComponent(appName, () => App);
// iOS uses Expo's stock scene delegate (ios/TurboImageBench/SceneDelegate.swift,
// from Expo's template), which starts the root component Expo apps register
// as "main"; Android's MainActivity asks for `appName`. Same app under both.
AppRegistry.registerComponent('main', () => App);
