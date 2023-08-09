#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(TurboImageViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(color, NSString)
RCT_EXPORT_VIEW_PROPERTY(source, NSString)
RCT_EXPORT_VIEW_PROPERTY(width, double)
RCT_EXPORT_VIEW_PROPERTY(height, double)
RCT_EXPORT_VIEW_PROPERTY(scaleMode, NSString)

@end
