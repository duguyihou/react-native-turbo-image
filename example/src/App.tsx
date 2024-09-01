import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import ProcessingScreen from './screens/ProcessingScreen';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HomeScreen from './screens/HomeScreen';
import { type HomeStackParamList, RouteName } from './screens/routes.type';
import SuccessScreen from './screens/events/SuccessScreen';
import FailureScreen from './screens/events/FailureScreen';
import ImageScreen from './screens/list/ImageScreen';
import UrlCacheScreen from './screens/list/UrlCacheScreen';
import DataCacheScreen from './screens/list/DataCacheScreen';
import SVGScreen from './screens/formats/SVGScreen';
import GifScreen from './screens/formats/GifScreen';
import PrefetchScreen from './screens/PrefetchScreen';
import ThumbhashScreen from './screens/placeholder/ThumbhashScreen';
import BlurhashScreen from './screens/placeholder/BlurhashScreen';
import LiveTextScreen from './screens/LiveTextScreen';
import APNGScreen from './screens/formats/APNGScreen';
import MemoryCacheKeyScreen from './screens/placeholder/MemoryCacheKeyScreen';
import MemoryCacheKeyPreviousScreen from './screens/placeholder/MemoryCacheKeyPreviousScreen';

const Stack = createNativeStackNavigator<HomeStackParamList>();

function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name={RouteName.Home} component={HomeScreen} />
        <Stack.Group>
          <Stack.Screen name={RouteName.Image} component={ImageScreen} />
          <Stack.Screen name={RouteName.UrlCache} component={UrlCacheScreen} />
          <Stack.Screen
            name={RouteName.DataCache}
            component={DataCacheScreen}
          />
        </Stack.Group>
        <Stack.Group>
          <Stack.Screen
            name={RouteName.Thumbhash}
            component={ThumbhashScreen}
          />
          <Stack.Screen name={RouteName.Blurhash} component={BlurhashScreen} />
          <Stack.Screen
            name={RouteName.MemoryCacheKeyPrevious}
            component={MemoryCacheKeyPreviousScreen}
          />
          <Stack.Screen
            name={RouteName.MemoryCacheKey}
            component={MemoryCacheKeyScreen}
          />
        </Stack.Group>
        <Stack.Group>
          <Stack.Screen name={RouteName.Prefetch} component={PrefetchScreen} />
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
        <Stack.Screen
          name={RouteName.LiveText}
          component={LiveTextScreen}
          options={{ title: 'Live Text (iOS 16+ only)' }}
        />
        <Stack.Group>
          <Stack.Screen name={RouteName.SVG} component={SVGScreen} />
          <Stack.Screen name={RouteName.Gif} component={GifScreen} />
          <Stack.Screen name={RouteName.APNG} component={APNGScreen} />
        </Stack.Group>
      </Stack.Navigator>
    </NavigationContainer>
  );
}

export default App;
