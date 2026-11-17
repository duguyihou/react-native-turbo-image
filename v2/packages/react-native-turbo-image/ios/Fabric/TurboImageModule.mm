// Cache-management TurboModule (iOS): prefetch, dispose, clearMemoryCache,
// clearDiskCache. Every source goes through the C++ core first, via the same
// factory the view uses, so prefetched entries are exactly the ones a view
// will later hit.

#import "TurboImageModule.h"

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

}  // namespace

@interface TurboImageModule () <NativeTurboImageModuleSpec>
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
    const auto built =
        TIMakeImageRequest(fields.uri, fields.cacheKey, policy, {}, 1, fields.headers);
    if (built.request == nil) {
      finishOne(NO);
      continue;
    }
    // Capture the set, not `self`: `weakSelf->_prefetches` would dereference
    // nil if the module were torn down mid-prefetch.
    NSMutableSet<id<TIImageLoadTask>> *prefetches = _prefetches;
    __block id<TIImageLoadTask> task = nil;
    task = [loader prefetchRequest:built.request
                        completion:^(BOOL succeeded) {
                          [prefetches removeObject:task];
                          finishOne(succeeded);
                        }];
    [prefetches addObject:task];
  }
}

- (void)dispose:(NSArray *)sources
        resolve:(RCTPromiseResolveBlock)resolve
         reject:(RCTPromiseRejectBlock)reject {
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  for (id source in sources) {
    const auto fields = sourceFields(source);
    // Policy and headers are irrelevant for the key; Default resolves it
    // like a view would.
    const auto built =
        TIMakeImageRequest(fields.uri, fields.cacheKey, turboimage::CachePolicy::Default);
    if (built.request != nil) {
      [loader removeCachedImageForKey:built.request.cacheKey];
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
