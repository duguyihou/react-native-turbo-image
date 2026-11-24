#import "TIImageLoaderRegistry+Testing.h"

NSErrorDomain const TIImageLoadErrorDomain = @"com.turboimage.load";

// Pinned by `@objc(TurboImageNukeLoader)` in NukeImageLoader.swift.
static NSString *const kDefaultLoaderClassName = @"TurboImageNukeLoader";

@implementation TIImageLoaderRegistry

static id<TIImageLoading> sSharedLoader;
static NSInteger sCacheMaxDiskSize;
static NSInteger sCacheMaxMemoryCost;

+ (BOOL)configureCacheWithMaxDiskSize:(NSInteger)maxDiskSize maxMemoryCost:(NSInteger)maxMemoryCost {
  @synchronized(self) {
    if (sSharedLoader != nil) {
      return NO;
    }
    sCacheMaxDiskSize = MAX(maxDiskSize, 0);
    sCacheMaxMemoryCost = MAX(maxMemoryCost, 0);
    return YES;
  }
}

// Called from the adapter's init inside `sharedLoader`'s lock (it is recursive).
+ (NSInteger)cacheMaxDiskSize {
  @synchronized(self) {
    return sCacheMaxDiskSize;
  }
}

+ (NSInteger)cacheMaxMemoryCost {
  @synchronized(self) {
    return sCacheMaxMemoryCost;
  }
}

// Found by class name: importing the Swift adapter would invert the layering
// and make a SwiftPM cycle. Trade-off: a typo fails at runtime (smoke test
// covers it).
+ (nullable id<TIImageLoading>)sharedLoader {
  @synchronized(self) {
    if (sSharedLoader == nil) {
      Class cls = NSClassFromString(kDefaultLoaderClassName);
      if ([cls conformsToProtocol:@protocol(TIImageLoading)]) {
        sSharedLoader = [cls new];
      }
    }
    return sSharedLoader;
  }
}

+ (void)setSharedLoaderForTesting:(nullable id<TIImageLoading>)loader {
  @synchronized(self) {
    sSharedLoader = loader;
  }
}

@end
