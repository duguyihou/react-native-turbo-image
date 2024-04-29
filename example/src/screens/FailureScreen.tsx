import { Text, View, type NativeSyntheticEvent } from 'react-native';
import React, { useState } from 'react';
import Card from '../components/Card';
import type { Failure } from 'react-native-turbo-image';

type Information = {
  error: string;
};
const FailureResultScreen = () => {
  const [information, setInformation] = useState<Information | null>(null);
  const handleFailure = ({ nativeEvent }: NativeSyntheticEvent<Failure>) => {
    setInformation(nativeEvent);
  };

  return (
    <View>
      <Card
        src="https://placedog.net/300/300?id=12100"
        size={[300, 300]}
        blurhash="UBIr4u9}00Rj?yEzxu%LIQ%1%6xt-ks,tAIU"
        onFailure={handleFailure}
      />
      {information?.error && <Text>error: {information?.error}</Text>}
    </View>
  );
};

export default FailureResultScreen;
