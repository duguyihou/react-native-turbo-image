import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import CacheScreen from './screens/CacheScreen';
import GridScreen from './screens/GridScreen';
import ImageProcessingScreen from './screens/ImageProcessingScreen';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HomeScreen from './screens/HomeScreen';
import { type HomeStackParamList, RouteName } from './screens/routes.type';
import SuccessResultScreen from './screens/SuccessResultScreen';
import FailureResultScreen from './screens/FailureResultScreen';

const Stack = createNativeStackNavigator<HomeStackParamList>();

function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name={RouteName.Home} component={HomeScreen} />
        <Stack.Screen name={RouteName.Cache} component={CacheScreen} />
        <Stack.Screen name={RouteName.Grid} component={GridScreen} />
        <Stack.Screen
          name={RouteName.ImageProcessing}
          component={ImageProcessingScreen}
          options={{ title: 'Image Processing' }}
        />
        <Stack.Screen
          name={RouteName.SuccessResult}
          component={SuccessResultScreen}
        />
        <Stack.Screen
          name={RouteName.FailureResult}
          component={FailureResultScreen}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

export default App;
