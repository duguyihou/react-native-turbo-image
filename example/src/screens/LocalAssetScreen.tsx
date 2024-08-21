import React from 'react';
import Card from '../components/Card';

const LocalAssetScreen = () => {
  return (
    <>
      <Card
        source={require('../../assets/local.png')}
        style={{ width: 200, height: 200 }}
        title="png"
      />
      <Card
        source={require('../../assets/Swift_logo.svg')}
        style={{ width: 190, height: 60 }}
        format="svg"
        title="svg"
      />
    </>
  );
};

export default LocalAssetScreen;
