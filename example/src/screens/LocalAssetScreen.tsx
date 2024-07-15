import React from 'react';
import { localAssetData } from '../data';
import Card from '../components/Card';

const LocalAssetScreen = () => {
  return (
    <>
      {localAssetData.map(({ url }) => {
        return (
          <Card
            key={url}
            source={require('../../assets/local.png')}
            size={200}
          />
        );
      })}
    </>
  );
};

export default LocalAssetScreen;
