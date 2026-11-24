#import "TILiveText.h"

// Pinned by `@objc(TurboImageLiveTextInteraction)` in LiveTextInteraction.swift.
// Looked up by name to keep layering (see TIImageLoaderRegistry.m).
static NSString *const kLiveTextClassName = @"TurboImageLiveTextInteraction";

id<TILiveTextInteraction> _Nullable TIMakeLiveTextInteraction(void) {
  // No OS check: iOS 16 is the floor. On tvOS the class is absent, so nil.
  Class cls = NSClassFromString(kLiveTextClassName);
  if (![cls conformsToProtocol:@protocol(TILiveTextInteraction)]) {
    return nil;
  }
  return [(Class<TILiveTextInteraction>)cls makeIfSupported];
}
