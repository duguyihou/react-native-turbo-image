/**
 * @format
 */

// First, and as a bare import: sizes TurboImage's caches before anything
// else touches TurboImage. A named import would not do, because Metro's
// inline requires defer a module until one of its values is first read.
// oxlint-disable-next-line import/no-unassigned-import -- run for its side effect
import './src/startup';
import { AppRegistry } from 'react-native';
import App from './App';
import { name as appName } from './app.json';

AppRegistry.registerComponent(appName, () => App);
