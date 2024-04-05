import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import CacheScreen from './screens/CacheScreen';
import GridScreen from './screens/GridScreen';
import ProcessScreen from './screens/ProcessScreen';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import HomeScreen from './screens/HomeScreen';
import { type HomeStackParamList, RouteName } from './screens/routes.type';

const Stack = createNativeStackNavigator<HomeStackParamList>();

function App() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name={RouteName.Home} component={HomeScreen} />
        <Stack.Screen name={RouteName.Cache} component={CacheScreen} />
        <Stack.Screen name={RouteName.Grid} component={GridScreen} />
        <Stack.Screen name={RouteName.Process} component={ProcessScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

export default App;
