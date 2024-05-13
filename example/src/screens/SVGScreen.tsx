import React from 'react';
import { svgData } from '../data';
import Card from '../components/Card';

const SVGScreen = () => {
  return (
    <>
      {svgData.map(({ url }) => {
        return <Card key={url} src={url} size={300} indicator="large" />;
      })}
    </>
  );
};

export default SVGScreen;
