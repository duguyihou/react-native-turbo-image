import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import TurboImageScreen from './screens/TurboImageScreen';
import ProcessingScreen from './screens/ProcessingScreen';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HomeScreen from './screens/HomeScreen';
import { type HomeStackParamList, RouteName } from './screens/routes.type';
import SuccessScreen from './screens/SuccessScreen';
import FailureScreen from './screens/FailureScreen';
import ImageScreen from './screens/ImageScreen';
import MemoryCacheScreen from './screens/MemoryCacheScreen';
import UrlCacheScreen from './screens/UrlCacheScreen';
import DataCacheScreen from './screens/DataCacheScreen';
import SVGScreen from './screens/SVGScreen';

const Stack = createNativeStackNavigator<HomeStackParamList>();

function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name={RouteName.Home} component={HomeScreen} />
        <Stack.Group>
          <Stack.Screen
            name={RouteName.TurboImage}
            component={TurboImageScreen}
          />
          <Stack.Screen name={RouteName.Image} component={ImageScreen} />
        </Stack.Group>
        <Stack.Group>
          <Stack.Screen
            name={RouteName.MemoryCache}
            component={MemoryCacheScreen}
          />
          <Stack.Screen name={RouteName.UrlCache} component={UrlCacheScreen} />
          <Stack.Screen
            name={RouteName.DataCache}
            component={DataCacheScreen}
          />
        </Stack.Group>
        <Stack.Group>
          <Stack.Screen name={RouteName.Success} component={SuccessScreen} />
          <Stack.Screen name={RouteName.Failure} component={FailureScreen} />
        </Stack.Group>
        <Stack.Screen
          name={RouteName.ImageProcessing}
          component={ProcessingScreen}
          options={{ title: 'Image Processing' }}
        />
        <Stack.Screen name={RouteName.SVG} component={SVGScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

export default App;
