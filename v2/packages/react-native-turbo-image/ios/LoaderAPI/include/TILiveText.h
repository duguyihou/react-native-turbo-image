// Live Text seam (iOS 16+), backing `enableLiveTextInteraction`.
//
// VisionKit's image-analysis API (`ImageAnalyzer`, `ImageAnalysisInteraction`)
// is Swift-only, but the Fabric view is ObjC++ and must not import Swift
// (RFC §4.7: no Swift/C++ interop, no `-Swift.h` across targets). So the
// Swift implementation (ios/LiveText) conforms to this plain-ObjC protocol and
// is found by class name, exactly like the Nuke adapter and
// `TIImageLoaderRegistry`.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns one VisionKit interaction for one image view. Main thread only.
NS_SWIFT_UI_ACTOR
@protocol TILiveTextInteraction <NSObject>

/// nil when the device cannot analyse images (`ImageAnalyzer.isSupported`)
/// or the OS is older than iOS 16.
+ (nullable id<TILiveTextInteraction>)makeIfSupported;

/// Attaches to `imageView` (once) and analyses `image`, replacing any
/// earlier analysis. An analysis still running for an older image is
/// cancelled and never applied.
- (void)analyzeImage:(UIImage *)image inImageView:(UIImageView *)imageView;

/// Cancels analysis and removes the interaction. Idempotent.
- (void)detach;

@end

/// Returns a new interaction from the bundled implementation, or nil if it
/// is unsupported here or not linked. Main thread.
FOUNDATION_EXPORT id<TILiveTextInteraction> _Nullable TIMakeLiveTextInteraction(void)
    NS_SWIFT_UI_ACTOR;

NS_ASSUME_NONNULL_END
