#import "TILiveText.h"

// The ObjC runtime name pinned by `@objc(TurboImageLiveTextInteraction)` in
// ios/LiveText/LiveTextInteraction.swift. Looked up by name for the same
// layering reason as the Nuke adapter (see TIImageLoaderRegistry.m); the smoke
// scenario `liveText` exercises the lookup.
static NSString *const kLiveTextClassName = @"TurboImageLiveTextInteraction";

id<TILiveTextInteraction> _Nullable TIMakeLiveTextInteraction(void) {
  // No OS check: the floor is iOS 16, VisionKit's own. On tvOS the Swift
  // class is compiled out, so the lookup below returns nil.
  Class cls = NSClassFromString(kLiveTextClassName);
  if (![cls conformsToProtocol:@protocol(TILiveTextInteraction)]) {
    return nil;
  }
  return [(Class<TILiveTextInteraction>)cls makeIfSupported];
}
