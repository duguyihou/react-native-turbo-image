#import "TIImageLoading.h"

// The ObjC runtime name pinned by `@objc(TurboImageNukeLoader)` in
// ios/Nuke/NukeImageLoader.swift.
static NSString *const kDefaultLoaderClassName = @"TurboImageNukeLoader";

@implementation TIImageLoaderRegistry

static id<TIImageLoading> sSharedLoader;

// The default adapter is resolved by class name instead of being referenced
// directly. Referencing it would require this C-family target to import the
// Swift adapter's generated `-Swift.h` header, i.e. a dependency from
// LoaderAPI → Nuke adapter. That inverts the layering (the adapter depends
// on the seam, not the other way round) and creates a cycle in SwiftPM.
//
// Trade-off: a typo in the class name fails at runtime, not at link time.
// The example app's smoke test exercises this lookup on every CI run.
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

+ (void)setSharedLoader:(nullable id<TIImageLoading>)sharedLoader {
  @synchronized(self) {
    sSharedLoader = sharedLoader;
  }
}

@end
