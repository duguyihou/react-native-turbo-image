import React from 'react';
import { urlCacheData } from '../data';
import Card from '../components/Card';
import type { CachePolicy } from 'react-native-turbo-image';

const UrlCacheScreen = () => {
  return (
    <>
      {urlCacheData.map(({ url, blurhash, cachePolicy }) => {
        return (
          <Card
            key={url}
            source={{
              uri: url,
            }}
            placeholder={{ blurhash }}
            cachePolicy={cachePolicy as CachePolicy}
            size={300}
          />
        );
      })}
    </>
  );
};

export default UrlCacheScreen;
