import { Pressable, StyleSheet, Text, View } from 'react-native';
import React, { useState } from 'react';
import TurboImage from '../../../../src';

const DynamaticUriScreen = () => {
  const [selected, setSelected] = useState(false);
  const handlePress = () => {
    setSelected((prev) => !prev);
  };
  return (
    <View>
      <TurboImage
        source={{
          uri: selected
            ? 'https://picsum.photos/id/15/300'
            : 'https://picsum.photos/id/16/300',
        }}
        style={styles.image}
      />
      <Pressable onPress={handlePress}>
        <Text style={styles.text}>Change Image</Text>
      </Pressable>
    </View>
  );
};

export default DynamaticUriScreen;

const styles = StyleSheet.create({
  image: {
    width: 300,
    height: 300,
    alignSelf: 'center',
  },

  text: {
    fontSize: 20,
    alignSelf: 'center',
    padding: 20,
    borderRadius: 5,
    borderWidth: 1,
  },
});
