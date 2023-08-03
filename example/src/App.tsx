import * as React from 'react';

import { StyleSheet, View } from 'react-native';
import { TurboImageView } from 'react-native-turbo-image';

export default function App() {
  return (
    <View style={styles.container}>
      <TurboImageView
        color="#32a852"
        style={styles.box}
        source="https://placebear.com/640/360"
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    width: 60,
    height: 60,
    marginVertical: 20,
  },
});
