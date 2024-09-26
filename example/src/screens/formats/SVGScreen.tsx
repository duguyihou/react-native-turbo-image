import React from 'react';
import { svgData } from './data';
import { StyleSheet, View } from 'react-native';
import TurboImage from 'react-native-turbo-image';

const SVGScreen = () => {
  return (
    <View>
      {svgData.map(({ uri }) => {
        return (
          <TurboImage
            key={uri}
            source={{ uri }}
            style={styles.image}
            indicator={{
              style: 'large',
              color: 'red',
            }}
            format="svg"
          />
        );
      })}
    </View>
  );
};

export default SVGScreen;

const styles = StyleSheet.create({
  image: {
    width: 190,
    height: 60,
    alignSelf: 'center',
  },
});
