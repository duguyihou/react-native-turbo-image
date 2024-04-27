import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import TurboImageScreen from './screens/TurboImageScreen';
import ImageProcessingScreen from './screens/ImageProcessingScreen';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HomeScreen from './screens/HomeScreen';
import { type HomeStackParamList, RouteName } from './screens/routes.type';
import SuccessResultScreen from './screens/SuccessResultScreen';
import FailureResultScreen from './screens/FailureResultScreen';
import ImageScreen from './screens/ImageScreen';
import MemoryCacheScreen from './screens/MemoryCacheScreen';
import UrlCacheScreen from './screens/UrlCacheScreen';
import DataCacheScreen from './screens/DataCacheScreen';

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

        <Stack.Screen
          name={RouteName.ImageProcessing}
          component={ImageProcessingScreen}
          options={{ title: 'Image Processing' }}
        />
        <Stack.Screen
          name={RouteName.Success}
          component={SuccessResultScreen}
        />
        <Stack.Screen
          name={RouteName.Failure}
          component={FailureResultScreen}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

export default App;
