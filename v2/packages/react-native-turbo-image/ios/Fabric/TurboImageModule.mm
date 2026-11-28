// Cache TurboModule (iOS). Uses the view's request factory, so prefetched
// entries match what a view later loads.

#import "TurboImageModule.h"

#import <React/RCTInvalidating.h>
#import <TurboImageSpec/TurboImageSpec.h>

#include <turboimage/ImageRequest.h>

#import "TIImageLoading.h"
#import "TIRequestFactory.h"

#include <vector>

namespace {

// `{ uri, cacheKey?, headers? }` from JS. Malformed input maps to values the
// core rejects, so a bad header fails rather than loads without auth.
struct SourceFields {
  std::string uri;
  std::string cacheKey;
  std::vector<turboimage::Header> headers;
};

std::string stringField(NSDictionary *dict, NSString *key) {
  id value = dict[key];
  return [value isKindOfClass:[NSString class]] ? std::string([(NSString *)value UTF8String]) : "";
}

SourceFields sourceFields(id source) {
  if (![source isKindOfClass:[NSDictionary class]]) {
    return {};
  }
  NSDictionary *dict = source;
  SourceFields fields{.uri = stringField(dict, @"uri"),
                      .cacheKey = stringField(dict, @"cacheKey"),
                      .headers = {}};
  id headers = dict[@"headers"];
  if ([headers isKindOfClass:[NSArray class]]) {
    for (id header in (NSArray *)headers) {
      NSDictionary *pair = [header isKindOfClass:[NSDictionary class]] ? header : @{};
      fields.headers.push_back(
          {.name = stringField(pair, @"name"), .value = stringField(pair, @"value")});
    }
  }
  return fields;
}

// The original image: the module has no view to size it for.
turboimage::ImageRequest coreRequest(const SourceFields &fields,
                                     turboimage::CachePolicy policy) {
  return {
      .uri = fields.uri,
      .cacheKey = TIOptionalCacheKey(fields.cacheKey),
      .cachePolicy = policy,
      .processing = {},
      .pixelRatio = 1,
      .headers = fields.headers,
      .allowDownscaling = false,
      .resizeMode = turboimage::ResizeMode::Contain,
  };
}

// Prefetch only downloads (memory write off = don't decode), unless there is
// no disk tier, or nothing would be stored.
TIImageRequest *diskOnly(TIImageRequest *request) {
  if (!request.diskCacheWrite) {
    return request;
  }
  return [[TIImageRequest alloc] initWithURL:request.url
                                    cacheKey:request.cacheKey
                             memoryCacheRead:request.memoryCacheRead
                            memoryCacheWrite:NO
                               diskCacheRead:request.diskCacheRead
                              diskCacheWrite:request.diskCacheWrite
                                allowNetwork:request.allowNetwork
                                processorKey:request.processorKey
                                   processor:request.processor
                                     headers:request.headers
                                   httpCache:request.httpCache
                                  decodeSize:request.decodeSize
                                  decodeFill:request.decodeFill
                            vectorDecodeSize:request.vectorDecodeSize
                            vectorDecodeFill:request.vectorDecodeFill
                                displayScale:request.displayScale];
}

}  // namespace

@interface TurboImageModule () <NativeTurboImageModuleSpec, RCTInvalidating>
@end

@implementation TurboImageModule {
  // In-flight prefetches, kept alive until they complete. Main thread only.
  NSMutableSet<id<TIImageLoadTask>> *_prefetches;
}

RCT_EXPORT_MODULE(TurboImageModule)

- (instancetype)init {
  if ((self = [super init])) {
    _prefetches = [NSMutableSet new];
  }
  return self;
}

// The loader seam is main-thread only (TIImageLoading.h).
- (dispatch_queue_t)methodQueue {
  return dispatch_get_main_queue();
}

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

- (void)prefetch:(NSArray *)sources
     cachePolicy:(NSString *)cachePolicy
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject {
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (loader == nil) {
    reject(@"unknown", @"No TurboImage loader adapter is linked", nil);
    return;
  }
  const auto policy = turboimage::parseCachePolicy(cachePolicy.UTF8String ?: "")
                          .value_or(turboimage::CachePolicy::Default);

  __block NSUInteger pending = sources.count;
  __block BOOL allSucceeded = YES;
  if (pending == 0) {
    resolve(@YES);
    return;
  }
  // Called once per source, on the main thread.
  void (^finishOne)(BOOL) = ^(BOOL succeeded) {
    allSucceeded = allSucceeded && succeeded;
    if (--pending == 0) {
      resolve(@(allSucceeded));
    }
  };

  for (id source in sources) {
    const auto fields = sourceFields(source);
    const auto built = TIMakeImageRequest(coreRequest(fields, policy));
    if (built.request == nil) {
      finishOne(NO);
      continue;
    }
    // Capture the set, not `self`, so teardown mid-prefetch is safe.
    NSMutableSet<id<TIImageLoadTask>> *prefetches = _prefetches;
    __block id<TIImageLoadTask> task = nil;
    task = [loader prefetchRequest:diskOnly(built.request)
                        completion:^(BOOL succeeded) {
                          [prefetches removeObject:task];
                          finishOne(succeeded);
                        }];
    [prefetches addObject:task];
  }
}

// Cancel prefetches on teardown. Promises stay unsettled: their runtime is
// going away too.
- (void)invalidate {
  // May arrive off main; `_prefetches` is main-only.
  NSMutableSet<id<TIImageLoadTask>> *prefetches = _prefetches;
  void (^cancelAll)(void) = ^{
    for (id<TIImageLoadTask> task in prefetches) {
      [task cancel];
    }
    [prefetches removeAllObjects];
  };
  if (NSThread.isMainThread) {
    cancelAll();
  } else {
    dispatch_async(dispatch_get_main_queue(), cancelAll);
  }
}

- (void)getSize:(NSDictionary *)source
    cachePolicy:(NSString *)cachePolicy
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject {
  // Rejection code is the `LoadErrorCode` name, as in `onFailure.code`.
  auto rejectWith = ^(turboimage::LoadErrorCode code, NSString *message) {
    const auto name = turboimage::loadErrorCodeName(code);
    reject([[NSString alloc] initWithBytes:name.data() length:name.size() encoding:NSUTF8StringEncoding],
           message, nil);
  };
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (loader == nil) {
    rejectWith(turboimage::LoadErrorCode::Unknown, @"No TurboImage loader adapter is linked");
    return;
  }
  const auto policy = turboimage::parseCachePolicy(cachePolicy.UTF8String ?: "")
                          .value_or(turboimage::CachePolicy::Default);
  const auto built = TIMakeImageRequest(coreRequest(sourceFields(source), policy));
  if (built.request == nil) {
    rejectWith(built.error, built.message);
    return;
  }
  // Kept alive like a prefetch.
  NSMutableSet<id<TIImageLoadTask>> *prefetches = _prefetches;
  __block id<TIImageLoadTask> task = nil;
  __block BOOL done = NO;
  task = [loader imageSizeForRequest:built.request
                          completion:^(CGSize size, NSError *error) {
                            done = YES;
                            if (task != nil) {
                              [prefetches removeObject:task];
                            }
                            if (error == nil) {
                              resolve(@{@"width" : @(size.width), @"height" : @(size.height)});
                              return;
                            }
                            rejectWith(TICoreErrorCode(error), error.localizedDescription);
                          }];
  if (!done) {
    [prefetches addObject:task];
  }
}

// Sync on the JS thread so it applies before the first image renders.
- (NSNumber *)configureCache:(double)maxDiskSize maxMemoryCost:(double)maxMemoryCost {
  return @([TIImageLoaderRegistry configureCacheWithMaxDiskSize:static_cast<NSInteger>(maxDiskSize)
                                                  maxMemoryCost:static_cast<NSInteger>(maxMemoryCost)]);
}

- (void)dispose:(NSArray *)sources
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject {
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  for (id source in sources) {
    const auto fields = sourceFields(source);
    // Policy doesn't affect key or URL.
    const auto built = TIMakeImageRequest(coreRequest(fields, turboimage::CachePolicy::Default));
    if (built.request != nil) {
      [loader removeCachedImageForRequest:built.request];
    }
  }
  resolve(nil);
}

- (void)clearMemoryCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  [TIImageLoaderRegistry.sharedLoader clearMemoryCache];
  resolve(nil);
}

- (void)clearDiskCache:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  [TIImageLoaderRegistry.sharedLoader clearDiskCache];
  resolve(nil);
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeTurboImageModuleSpecJSI>(params);
}

@end
