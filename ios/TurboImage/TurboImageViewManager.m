#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(TurboImageViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(url, NSString)

RCT_EXPORT_VIEW_PROPERTY(onError, RCTDirectEventBlock)

RCT_EXPORT_VIEW_PROPERTY(onSuccess, RCTDirectEventBlock)

RCT_EXPORT_VIEW_PROPERTY(resizeMode, NSString)

@end

