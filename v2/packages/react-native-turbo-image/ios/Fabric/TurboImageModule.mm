// Cache-management TurboModule (iOS): prefetch, dispose, clearMemoryCache,
// clearDiskCache. Every source goes through the C++ core first, via the same
// factory the view uses, so prefetched entries are exactly the ones a view
// will later hit.

#import "TurboImageModule.h"

#import <React/RCTInvalidating.h>
#import <TurboImageSpec/TurboImageSpec.h>

#include <turboimage/ImageRequest.h>

#import "TIImageLoading.h"
#import "TIRequestFactory.h"

#include <vector>

namespace {

// `{ uri, cacheKey?, headers? }` from JS (headers already normalised to
// `[{name, value}]` by index.tsx). Anything malformed becomes something the
// core rejects: a non-dictionary source an empty URI, a malformed header an
// empty name (InvalidHeader), so a bad source fails instead of loading
// without its auth header.
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

// A request for the original image: no processors, and no downscaling,
// because the module has no view to size a decode for. Prefetch therefore
// fills the disk cache with the original bytes (which every view variant is
// derived from) and the memory cache with the full-size image.
turboimage::ImageRequest coreRequest(const SourceFields &fields, turboimage::CachePolicy policy) {
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

// `destination: 'disk'`: the same request with the memory write off, which
// tells the adapter not to decode at all (`prefetchRequest:completion:`). A
// request with no disk tier (`memoryOnly`, a local file) is kept as it is,
// or the prefetch would store nothing.
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
     destination:(NSString *)destination
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject {
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (loader == nil) {
    reject(@"unknown", @"No TurboImage loader adapter is linked", nil);
    return;
  }
  const auto policy = turboimage::parseCachePolicy(cachePolicy.UTF8String ?: "")
                          .value_or(turboimage::CachePolicy::Default);
  const BOOL toDiskOnly = [destination isEqualToString:@"disk"];

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
    // Capture the set, not `self`: `weakSelf->_prefetches` would dereference
    // nil if the module were torn down mid-prefetch.
    NSMutableSet<id<TIImageLoadTask>> *prefetches = _prefetches;
    __block id<TIImageLoadTask> task = nil;
    task = [loader prefetchRequest:toDiskOnly ? diskOnly(built.request) : built.request
                        completion:^(BOOL succeeded) {
                          [prefetches removeObject:task];
                          finishOne(succeeded);
                        }];
    [prefetches addObject:task];
  }
}

// The module is going away (reload, or the host is destroyed): stop the
// prefetches it started. Their promises are left unsettled on purpose; the
// JS runtime they belong to is being torn down too.
- (void)invalidate {
  // `_prefetches` is main-thread only, and nothing promises which thread
  // this arrives on. The set is captured, not `self` (see prefetch).
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
  // The rejection code is the failure's `turboimage::LoadErrorCode` name, as
  // in `onFailure.code`.
  auto rejectWith = ^(turboimage::LoadErrorCode code, NSString *message) {
    const auto name = turboimage::loadErrorCodeName(code);
    reject([[NSString alloc] initWithBytes:name.data() length:name.size() encoding:NSUTF8StringEncoding],
           message, nil);
  };
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (![loader respondsToSelector:@selector(imageSizeForRequest:completion:)]) {
    rejectWith(turboimage::LoadErrorCode::Unknown,
               loader == nil ? @"No TurboImage loader adapter is linked"
                             : @"This loader adapter does not report image sizes");
    return;
  }
  const auto policy = turboimage::parseCachePolicy(cachePolicy.UTF8String ?: "")
                          .value_or(turboimage::CachePolicy::Default);
  const auto built = TIMakeImageRequest(coreRequest(sourceFields(source), policy));
  if (built.request == nil) {
    rejectWith(built.error, built.message);
    return;
  }
  // Kept like a prefetch until it settles (see prefetch for the capture).
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
                            // The seam promises TIImageLoadErrorDomain;
                            // anything else is an adapter bug, reported as
                            // unknown.
                            const auto code = [error.domain isEqualToString:TIImageLoadErrorDomain]
                                                  ? static_cast<turboimage::LoadErrorCode>(error.code)
                                                  : turboimage::LoadErrorCode::Unknown;
                            rejectWith(code, error.localizedDescription);
                          }];
  if (!done) {
    [prefetches addObject:task];
  }
}

// Synchronous, on the JS thread, so it has taken effect before the app
// renders its first image; the registry is thread-safe.
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
    // The policy is irrelevant for the key and the URL; Default resolves
    // them like a view would.
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
