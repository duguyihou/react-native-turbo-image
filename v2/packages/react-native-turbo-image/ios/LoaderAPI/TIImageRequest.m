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
                  httpCache:(BOOL)httpCache
                 decodeSize:(CGSize)decodeSize
                 decodeFill:(BOOL)decodeFill
           vectorDecodeSize:(CGSize)vectorDecodeSize
           vectorDecodeFill:(BOOL)vectorDecodeFill
               displayScale:(CGFloat)displayScale {
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
    _httpCache = httpCache;
    _decodeSize = decodeSize;
    _decodeFill = decodeFill;
    _vectorDecodeSize = vectorDecodeSize;
    _vectorDecodeFill = vectorDecodeFill;
    _displayScale = displayScale;
  }
  return self;
}

@end
