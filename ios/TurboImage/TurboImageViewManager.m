#import <React/RCTViewManager.h>

@interface RCT_EXTERN_MODULE(TurboImageViewManager, RCTViewManager)

#pragma mark - properties

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

#pragma mark - methods

RCT_EXTERN_METHOD(prefetch:(NSArray *)urlArray 
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(clearAllCache:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(clearMemoryCache:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(clearDiskCache:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

@end

