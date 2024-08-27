import React from 'react';
import { dataCacheData } from '../data';
import Card from '../components/Card';
import type { CachePolicy } from 'react-native-turbo-image';

const DataCacheScreen = () => {
  return (
    <>
      {dataCacheData.map(({ url, blurhash, cachePolicy }) => {
        return (
          <Card
            key={url}
            source={{ uri: url }}
            placeholder={{ blurhash }}
            cachePolicy={cachePolicy as CachePolicy}
            style={{ width: 300, height: 300 }}
          />
        );
      })}
    </>
  );
};

export default DataCacheScreen;
