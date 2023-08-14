#import <React/RCTViewManager.h>
#import "ReactNativeTurboImage-umbrella.h"
//#import <ReactNativeTurboImage/ReactNativeTurboImage-Swift.h>

@interface RCT_EXTERN_MODULE(TurboImageViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(color, NSString)
RCT_EXPORT_VIEW_PROPERTY(source, Source)
RCT_EXPORT_VIEW_PROPERTY(width, double)
RCT_EXPORT_VIEW_PROPERTY(height, double)
RCT_EXPORT_VIEW_PROPERTY(scaleMode, ScaleMode)

@end

