import { Text, View } from 'react-native';
import React, { useState } from 'react';
import Card from '../components/Card';
import type { FailureResult } from 'react-native-turbo-image';

type Information = {
  error: string;
};
const FailureResultScreen = () => {
  const [information, setInformation] = useState<Information | null>(null);
  const handleSuccess = ({ nativeEvent }: FailureResult) => {
    setInformation(nativeEvent);
  };

  return (
    <View>
      <Card
        src="https://placedog.net/300/300?id=12100"
        size={300}
        onError={handleSuccess}
      />
      {information?.error && <Text>error: {information?.error}</Text>}
    </View>
  );
};

export default FailureResultScreen;
