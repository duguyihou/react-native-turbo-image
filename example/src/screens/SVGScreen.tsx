import React from 'react';
import { svgData } from '../data';
import Card from '../components/Card';

const SVGScreen = () => {
  return (
    <>
      {svgData.map(({ url, isSVG }) => {
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
            isSVG={isSVG}
          />
        );
      })}
    </>
  );
};

export default SVGScreen;
