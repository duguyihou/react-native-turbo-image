import {
  StyleSheet,
  Text,
  View,
  type NativeSyntheticEvent,
} from 'react-native';
import React, { useState } from 'react';
import Card from '../../components/Card';
import type { Success, TaskState } from 'react-native-turbo-image';

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

  const handleStart = ({ nativeEvent }: NativeSyntheticEvent<TaskState>) => {
    setStart(nativeEvent.state === 'running');
  };

  const handleCompletion = ({
    nativeEvent,
  }: NativeSyntheticEvent<TaskState>) => {
    setCompletion(nativeEvent.state === 'completed');
  };

  return (
    <View style={styles.container}>
      <Card
        source={{
          uri: 'https://placedog.net/300/300?id=121',
        }}
        style={styles.image}
        cachePolicy="dataCache"
        onStart={handleStart}
        onSuccess={handleSuccess}
        onCompletion={handleCompletion}
        placeholder={{
          blurhash: 'UBIr4u9}00Rj?yEzxu%LIQ%1%6xt-ks,tAIU',
        }}
      />

      {start && <Text>Start at {Date()}</Text>}
      {information?.width && <Text>width: {information?.width}</Text>}
      {information?.height && <Text>height: {information?.height}</Text>}
      {information?.source && <Text>source: {information?.source}</Text>}
      {completion && <Text>Complete at {Date()}</Text>}
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
  image: {
    width: 300,
    height: 300,
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
