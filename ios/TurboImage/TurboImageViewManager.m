#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(TurboImageViewManager, RCTViewManager)

RCT_EXPORT_VIEW_PROPERTY(url, NSString)

RCT_EXPORT_VIEW_PROPERTY(resizeMode, NSString)

RCT_EXPORT_VIEW_PROPERTY(showActivityIndicator, BOOL)

RCT_EXPORT_VIEW_PROPERTY(base64Placeholder, NSString)

RCT_EXPORT_VIEW_PROPERTY(fadeDuration, NSNumber)

RCT_EXPORT_VIEW_PROPERTY(rounded, BOOL)

RCT_REMAP_VIEW_PROPERTY(tintColor, tint, UIColor)

RCT_EXPORT_VIEW_PROPERTY(cachePolicy, NSString)

RCT_EXPORT_VIEW_PROPERTY(onSuccess, RCTDirectEventBlock)

RCT_EXPORT_VIEW_PROPERTY(onError, RCTDirectEventBlock)

@end

