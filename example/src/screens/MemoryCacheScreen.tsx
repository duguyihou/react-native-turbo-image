import React from 'react';
import { memoryCacheData } from '../data';
import Card from '../components/Card';
import type { CachePolicy } from 'react-native-turbo-image';

const MemoryCacheScreen = () => {
  return (
    <>
      {memoryCacheData.map(({ url, blurhash, cachePolicy }) => {
        return (
          <Card
            key={url}
            src={url}
            blurhash={blurhash}
            cachePolicy={cachePolicy as CachePolicy}
            size={[300, 300]}
          />
        );
      })}
    </>
  );
};

export default MemoryCacheScreen;
