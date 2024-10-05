import {
  StyleSheet,
  Text,
  View,
  type NativeSyntheticEvent,
} from 'react-native';
import React, { useState } from 'react';
import type {
  Progress,
  Success,
  Start,
  Completion,
} from 'react-native-turbo-image';
import TurboImage from 'react-native-turbo-image';

type Information = {
  width: number;
  height: number;
  source: string;
};
const SuccessScreen = () => {
  const [start, setStart] = useState(false);
  const [progress, setProgress] = useState<string[]>([]);
  const [completion, setCompletion] = useState(false);

  const [information, setInformation] = useState<Information | null>(null);
  const handleSuccess = ({ nativeEvent }: NativeSyntheticEvent<Success>) => {
    setInformation(nativeEvent);
  };

  const handleStart = ({ nativeEvent }: NativeSyntheticEvent<Start>) => {
    setStart(nativeEvent.state === 'running');
  };

  const handleCompletion = ({
    nativeEvent,
  }: NativeSyntheticEvent<Completion>) => {
    setCompletion(nativeEvent.state === 'completed');
  };

  const handleProgress = ({ nativeEvent }: NativeSyntheticEvent<Progress>) => {
    const percentage = `${(
      (100 * nativeEvent.completed) /
      nativeEvent.total
    ).toFixed(2)}%`;
    setProgress((prev) => [...prev, percentage]);
  };

  return (
    <View style={styles.container}>
      <TurboImage
        source={{
          uri: 'https://picsum.photos/id/57/2000',
        }}
        style={styles.image}
        cachePolicy="dataCache"
        onStart={handleStart}
        onSuccess={handleSuccess}
        onCompletion={handleCompletion}
        onProgress={handleProgress}
        placeholder={{
          thumbhash: 'lOcNFwYGpmmNdIiJh4aHiId4aPwmlm8E',
        }}
      />

      {start && <Text>Start at {Date()}</Text>}
      {progress.length > 0 && <Text>Progress: {progress}</Text>}
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
