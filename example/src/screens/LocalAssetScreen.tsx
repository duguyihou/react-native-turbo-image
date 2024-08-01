import React from 'react';
import Card from '../components/Card';

const LocalAssetScreen = () => {
  return (
    <Card
      source={require('../../assets/local.png')}
      style={{ width: 200, height: 200 }}
    />
  );
};

export default LocalAssetScreen;
