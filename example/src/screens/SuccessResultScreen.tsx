import { Text, View } from 'react-native';
import React, { useState } from 'react';
import Card from '../components/Card';
import type { SuccessResult } from 'react-native-turbo-image';

type Information = {
  width: number;
  height: number;
  source: string;
};
const SuccessResultScreen = () => {
  const [information, setInformation] = useState<Information | null>(null);
  const handleSuccess = ({ nativeEvent }: SuccessResult) => {
    setInformation(nativeEvent);
  };

  return (
    <View>
      <Card
        src="https://placedog.net/300/300?id=121"
        size={300}
        onSuccess={handleSuccess}
      />
      {information?.width && <Text>width: {information?.width}</Text>}
      {information?.height && <Text>height: {information?.height}</Text>}
      {information?.source && <Text>source: {information?.source}</Text>}
    </View>
  );
};

export default SuccessResultScreen;
