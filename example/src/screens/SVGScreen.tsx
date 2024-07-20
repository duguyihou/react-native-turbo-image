import React from 'react';
import { svgData } from '../data';
import Card from '../components/Card';

const SVGScreen = () => {
  return (
    <>
      {svgData.map(({ url }) => {
        return (
          <Card
            key={url}
            source={{
              uri: url,
            }}
            size={[190, 60]}
            indicator={{
              style: 'large',
              color: 'red',
            }}
            format="svg"
          />
        );
      })}
    </>
  );
};

export default SVGScreen;
