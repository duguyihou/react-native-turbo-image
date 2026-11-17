#import "TILiveText.h"

// The ObjC runtime name pinned by `@objc(TurboImageLiveTextInteraction)` in
// ios/LiveText/LiveTextInteraction.swift. Looked up by name for the same
// layering reason as the Nuke adapter (see TIImageLoaderRegistry.m); the smoke
// scenario `liveText` exercises the lookup.
static NSString *const kLiveTextClassName = @"TurboImageLiveTextInteraction";

id<TILiveTextInteraction> _Nullable TIMakeLiveTextInteraction(void) {
  // The Swift class is registered with the runtime on iOS 15 too (only its
  // VisionKit calls are gated), so the OS check has to happen here.
  if (@available(iOS 16.0, *)) {
  } else {
    return nil;
  }
  Class cls = NSClassFromString(kLiveTextClassName);
  if (![cls conformsToProtocol:@protocol(TILiveTextInteraction)]) {
    return nil;
  }
  return [(Class<TILiveTextInteraction>)cls makeIfSupported];
}
