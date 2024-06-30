import React from 'react';
import { svgData } from '../data';
import Card from '../components/Card';
import type { Format } from 'react-native-turbo-image';

const SVGScreen = () => {
  return (
    <>
      {svgData.map(({ url, format }) => {
        return (
          <Card
            key={url}
            source={{
              uri: url,
            }}
            size={300}
            indicator={{
              style: 'large',
              color: 'red',
            }}
            format={format as Format}
          />
        );
      })}
    </>
  );
};

export default SVGScreen;
