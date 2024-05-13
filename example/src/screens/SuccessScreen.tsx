import { Text, View, type NativeSyntheticEvent } from 'react-native';
import React, { useState } from 'react';
import Card from '../components/Card';
import type { Start, Success } from 'react-native-turbo-image';

type Information = {
  width: number;
  height: number;
  source: string;
};
const SuccessScreen = () => {
  const [start, setStart] = useState(false);
  const [information, setInformation] = useState<Information | null>(null);
  const handleSuccess = ({ nativeEvent }: NativeSyntheticEvent<Success>) => {
    setInformation(nativeEvent);
  };

  const handleStart = ({ nativeEvent }: NativeSyntheticEvent<Start>) => {
    setStart(nativeEvent.state === 'running');
  };

  return (
    <View>
      <Card
        src="https://placedog.net/300/300?id=121"
        size={200}
        resize={200}
        onStart={handleStart}
        onSuccess={handleSuccess}
        blurhash="UBIr4u9}00Rj?yEzxu%LIQ%1%6xt-ks,tAIU"
      />

      {start && <Text>Start at {Date()}</Text>}
      {information?.width && <Text>width: {information?.width}</Text>}
      {information?.height && <Text>height: {information?.height}</Text>}
      {information?.source && <Text>source: {information?.source}</Text>}
    </View>
  );
};

export default SuccessScreen;
