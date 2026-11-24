// Loader seam (iOS): the only contract between the Fabric view and the Swift
// adapter. Plain ObjC so Swift needs no C++ interop and Nuke types never leak.
// Internal (ADR 0014); tests swap in a fake loader. Keep this dir C++-free.

#import <UIKit/UIKit.h>

#import "TIImageRequest.h"

NS_ASSUME_NONNULL_BEGIN

/// One in-flight load. `cancel` is idempotent and safe after completion.
@protocol TIImageLoadTask <NSObject>
- (void)cancel;
@end

/// Domain for all adapter errors. Codes mirror `turboimage::LoadErrorCode`;
/// the values are a pinned ABI.
FOUNDATION_EXPORT NSErrorDomain const TIImageLoadErrorDomain;

typedef NS_ERROR_ENUM(TIImageLoadErrorDomain, TIImageLoadErrorCode){
    TIImageLoadErrorUnknown = 0,
    TIImageLoadErrorInvalidRequest = 1,
    TIImageLoadErrorNotCached = 2,
    TIImageLoadErrorNetwork = 3,
    TIImageLoadErrorDecode = 4,
};

/// Called once on the main thread, or maybe never after cancel. Errors are in
/// `TIImageLoadErrorDomain`. `fromMemoryCache` skips the fade (like Coil).
/// `image` is a still (first frame if animated); `animation` is opaque and
/// only goes back to this loader's `displayImage:animation:inImageView:`.
typedef void (^TIImageLoadCompletion)(UIImage *_Nullable image,
                                      id _Nullable animation,
                                      BOOL fromMemoryCache,
                                      NSError *_Nullable error);

/// Bytes received / expected (`total` <= 0 if unknown). Main thread, only
/// before completion, never after cancel. Unthrottled; the view throttles.
typedef void (^TIImageLoadProgress)(int64_t completed, int64_t total);

@protocol TIImageLoading <NSObject>
- (id<TIImageLoadTask>)loadImageWithRequest:(TIImageRequest *)request
                                   progress:(nullable TIImageLoadProgress)progress
                                 completion:(TIImageLoadCompletion)completion;

// Display. The view decides what shows when; the loader only supplies the
// image view and plays animations in it.

/// A new image view for one TurboImage view. Main thread. Setting `image`
/// must stop any playing animation.
- (UIImageView *)makeImageView NS_SWIFT_UI_ACTOR;

/// Shows a load result, playing `animation` if any. Main thread. `imageView`
/// may not be from `makeImageView` (loader swapped); still show `image` then.
- (void)displayImage:(UIImage *)image
           animation:(nullable id)animation
         inImageView:(UIImageView *)imageView NS_SWIFT_UI_ACTOR;

// Cache management for TurboImageModule. Keys come from the core, so views
// and the module agree.

/// Loads into the caches. `completion` once on main, never after cancel.
/// With `memoryCacheWrite` off, store the bytes without decoding.
- (id<TIImageLoadTask>)prefetchRequest:(TIImageRequest *)request
                            completion:(void (^)(BOOL succeeded))completion;

/// Evicts every memory variant, the disk entry and the HTTP cache entry for
/// `cacheKey`/`url`. Main thread, no disk I/O inline: gone for the next read
/// on return, files deleted later (hence no completion, unlike Android).
- (void)removeCachedImageForRequest:(TIImageRequest *)request;

- (void)clearMemoryCache;
/// Empties both disk stores. Same threading as `removeCachedImageForRequest:`.
- (void)clearDiskCache;

/// Memory-only lookup for the `memoryCacheKey` placeholder. Main thread, cheap.
- (nullable UIImage *)memoryCachedImageForKey:(NSString *)cacheKey;

/// `TurboImage.getSize`: caches like `prefetchRequest:`, then reports the
/// oriented pixel size (from the header, not a decode) or the error.
/// `completion` once on main, never after cancel.
- (id<TIImageLoadTask>)imageSizeForRequest:(TIImageRequest *)request
                                completion:(void (^)(CGSize size, NSError *_Nullable error))completion;
@end

/// Process-wide loader selection. Thread-safe.
@interface TIImageLoaderRegistry : NSObject

/// The bundled Nuke adapter, found by name; nil if not linked.
@property(class, atomic, readonly, nullable) id<TIImageLoading> sharedLoader;

/// `TurboImage.configureCache`: sizes in bytes (0 = default). Only works
/// before `sharedLoader` exists; returns NO after.
+ (BOOL)configureCacheWithMaxDiskSize:(NSInteger)maxDiskSize maxMemoryCost:(NSInteger)maxMemoryCost;
@property(class, atomic, readonly) NSInteger cacheMaxDiskSize;
@property(class, atomic, readonly) NSInteger cacheMaxMemoryCost;

@end

NS_ASSUME_NONNULL_END
