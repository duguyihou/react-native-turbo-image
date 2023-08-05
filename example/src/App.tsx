import React from 'react';

import { StyleSheet, View } from 'react-native';
import TurboImage from 'react-native-turbo-image';

export default function App() {
  return (
    <View style={styles.container}>
      <TurboImage
        source="https://picsum.photos/seed/picsum/200/300"
        style={styles.box}
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
    width: 300,
    height: 200,
    marginVertical: 20,
  },
});
