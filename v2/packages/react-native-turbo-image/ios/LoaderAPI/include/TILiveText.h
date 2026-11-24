// Live Text seam (iOS only) for `enableLiveTextInteraction`. VisionKit is
// Swift-only and the Fabric view can't import Swift (RFC §4.7), so the Swift
// side conforms to this ObjC protocol and is found by class name.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Owns one VisionKit interaction for one image view. Main thread only.
NS_SWIFT_UI_ACTOR
@protocol TILiveTextInteraction <NSObject>

/// nil when the device cannot analyse images (`ImageAnalyzer.isSupported`).
+ (nullable id<TILiveTextInteraction>)makeIfSupported;

/// Attaches to `imageView` once and analyses `image`. A stale analysis is
/// cancelled and never applied.
- (void)analyzeImage:(UIImage *)image inImageView:(UIImageView *)imageView;

/// Cancels analysis and removes the interaction. Idempotent.
- (void)detach;

@end

/// A new interaction, or nil if unsupported (always on tvOS) or not linked.
/// Main thread.
FOUNDATION_EXPORT id<TILiveTextInteraction> _Nullable TIMakeLiveTextInteraction(void)
    NS_SWIFT_UI_ACTOR;

NS_ASSUME_NONNULL_END
