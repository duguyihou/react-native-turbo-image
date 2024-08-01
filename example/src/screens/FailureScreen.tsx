import { Text, View, type NativeSyntheticEvent } from 'react-native';
import React, { useState } from 'react';
import Card from '../components/Card';
import type { Failure, TaskState } from 'react-native-turbo-image';

type Information = {
  error: string;
};
const FailureResultScreen = () => {
  const [start, setStart] = useState(false);
  const [completion, setCompletion] = useState(false);
  const [information, setInformation] = useState<Information | null>(null);
  const handleFailure = ({ nativeEvent }: NativeSyntheticEvent<Failure>) => {
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
    <View>
      <Card
        source={{
          uri: 'https://placedog.net/300/300?id=12100',
        }}
        style={{ width: 200, height: 200 }}
        placeholder={{ blurhash: 'UBIr4u9}00Rj?yEzxu%LIQ%1%6xt-ks,tAIU' }}
        onStart={handleStart}
        onFailure={handleFailure}
        onCompletion={handleCompletion}
        showPlaceholderOnFailure
      />
      {start && <Text>Start at {Date()}</Text>}
      {information?.error && <Text>error: {information?.error}</Text>}
      {completion && <Text>Complete at {Date()}</Text>}
    </View>
  );
};

export default FailureResultScreen;
