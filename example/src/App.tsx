import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import CacheScreen from './screens/CacheScreen';
import ListScreen from './screens/ListScreen';
import ProcessScreen from './screens/ProcessScreen';

const Tab = createBottomTabNavigator();

function App() {
  return (
    <NavigationContainer>
      <Tab.Navigator>
        <Tab.Screen name="Cache" component={CacheScreen} />
        <Tab.Screen name="List" component={ListScreen} />
        <Tab.Screen name="Process" component={ProcessScreen} />
      </Tab.Navigator>
    </NavigationContainer>
  );
}

export default App;
