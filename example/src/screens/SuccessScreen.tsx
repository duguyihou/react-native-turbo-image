import {
  Pressable,
  StyleSheet,
  Text,
  View,
  type NativeSyntheticEvent,
} from 'react-native';
import React, { useState } from 'react';
import Card from '../components/Card';
import type { Success, TaskState } from 'react-native-turbo-image';
import { useNavigation } from '@react-navigation/native';
import { RouteName, type HomeStackNavigationProps } from './routes.type';

type Information = {
  width: number;
  height: number;
  source: string;
};
const SuccessScreen = () => {
  const [start, setStart] = useState(false);
  const [completion, setCompletion] = useState(false);

  const [information, setInformation] = useState<Information | null>(null);
  const handleSuccess = ({ nativeEvent }: NativeSyntheticEvent<Success>) => {
    setInformation(nativeEvent);
  };
  const navigation = useNavigation<HomeStackNavigationProps>();

  const handleStart = ({ nativeEvent }: NativeSyntheticEvent<TaskState>) => {
    setStart(nativeEvent.state === 'running');
  };

  const handleCompletion = ({
    nativeEvent,
  }: NativeSyntheticEvent<TaskState>) => {
    setCompletion(nativeEvent.state === 'completed');
  };
  const navigateToDetailScreen = () => {
    navigation.navigate(RouteName.Detail, {
      memoryCacheKey: 'https://placedog.net/100/100?id=121',
    });
  };
  return (
    <View style={styles.container}>
      <Card
        source={{
          uri: 'https://placedog.net/100/100?id=121',
        }}
        style={{ width: 100, height: 100 }}
        onStart={handleStart}
        onSuccess={handleSuccess}
        onCompletion={handleCompletion}
        onFailure={({ nativeEvent }) => console.log(nativeEvent.error)}
        placeholder={{
          blurhash: 'UBIr4u9}00Rj?yEzxu%LIQ%1%6xt-ks,tAIU',
        }}
      />

      {start && <Text>Start at {Date()}</Text>}
      {information?.width && <Text>width: {information?.width}</Text>}
      {information?.height && <Text>height: {information?.height}</Text>}
      {information?.source && <Text>source: {information?.source}</Text>}
      {completion && <Text>Complete at {Date()}</Text>}
      <Pressable style={styles.button} onPress={navigateToDetailScreen}>
        <Text style={styles.text}>Go to detail</Text>
      </Pressable>
    </View>
  );
};

export default SuccessScreen;

const styles = StyleSheet.create({
  container: {
    height: '100%',
    width: '100%',
    alignItems: 'center',
  },
  button: {
    marginHorizontal: 10,
    padding: 10,
    backgroundColor: 'black',
    borderRadius: 50,
    color: 'white',
    position: 'absolute',
    bottom: 50,
  },
  text: {
    fontSize: 20,
    textAlign: 'center',
    color: 'white',
  },
});
