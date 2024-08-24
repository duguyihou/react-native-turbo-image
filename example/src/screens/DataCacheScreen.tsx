import React from 'react';
import { dataCacheData } from '../data';
import Card from '../components/Card';

const DataCacheScreen = () => {
  return (
    <>
      {dataCacheData.map(({ uri, blurhash }) => {
        return (
          <Card
            key={uri}
            source={{ uri }}
            placeholder={{ blurhash }}
            cachePolicy="dataCache"
            style={{ width: 300, height: 300 }}
          />
        );
      })}
    </>
  );
};

export default DataCacheScreen;
