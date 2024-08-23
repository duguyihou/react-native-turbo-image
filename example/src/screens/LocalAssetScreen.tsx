import React from 'react';
import Card from '../components/Card';
import { ScrollView } from 'react-native';

const LocalAssetScreen = () => {
  return (
    <ScrollView>
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
      <Card
        source={require('../../assets/gif.gif')}
        style={{ width: 300, height: 300 }}
        format="gif"
        title="gif"
      />
      <Card
        source={require('../../assets/apng.png')}
        style={{ width: 300, height: 300 }}
        format="apng"
        title="apng"
      />
    </ScrollView>
  );
};

export default LocalAssetScreen;
