#import "TIImageRequest.h"

@implementation TIImageRequest

- (instancetype)initWithURL:(NSURL *)url
                   cacheKey:(NSString *)cacheKey
            memoryCacheRead:(BOOL)memoryCacheRead
           memoryCacheWrite:(BOOL)memoryCacheWrite
              diskCacheRead:(BOOL)diskCacheRead
             diskCacheWrite:(BOOL)diskCacheWrite
               allowNetwork:(BOOL)allowNetwork
               processorKey:(NSString *)processorKey
                  processor:(TIImageProcessor)processor
                    headers:(NSArray<NSArray<NSString *> *> *)headers
                 decodeSize:(CGSize)decodeSize
                 decodeFill:(BOOL)decodeFill {
  if ((self = [super init])) {
    _url = [url copy];
    _cacheKey = [cacheKey copy];
    _memoryCacheRead = memoryCacheRead;
    _memoryCacheWrite = memoryCacheWrite;
    _diskCacheRead = diskCacheRead;
    _diskCacheWrite = diskCacheWrite;
    _allowNetwork = allowNetwork;
    _processorKey = [processorKey copy];
    _processor = [processor copy];
    _headers = [headers copy];
    _decodeSize = decodeSize;
    _decodeFill = decodeFill;
  }
  return self;
}

@end
