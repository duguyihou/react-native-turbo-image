import React from 'react';
import { svgData } from './data';
import Card from '../../components/Card';

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
            style={{ width: 190, height: 60 }}
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
