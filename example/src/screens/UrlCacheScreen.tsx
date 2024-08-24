import React from 'react';
import { urlCacheData } from '../data';
import Card from '../components/Card';

const UrlCacheScreen = () => {
  return (
    <>
      {urlCacheData.map(({ uri, blurhash }) => {
        return (
          <Card
            key={uri}
            source={{ uri }}
            placeholder={{ blurhash }}
            cachePolicy="urlCache"
            style={{ width: 300, height: 300 }}
          />
        );
      })}
    </>
  );
};

export default UrlCacheScreen;
