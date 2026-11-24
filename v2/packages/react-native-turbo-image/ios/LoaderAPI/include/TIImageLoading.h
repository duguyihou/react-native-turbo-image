// TurboImage loader seam (iOS).
//
// This is the only contract between the Fabric view (ObjC++) and an image
// loader adapter (Swift, e.g. Nuke). It is deliberately plain Objective-C:
//
//   * Swift can conform to it without C++ interop, so the Swift adapter
//     target stays free of C-family sources (RFC rule 5) and does not force
//     `-cxx-interoperability-mode` onto everything that imports it.
//   * It exposes no loader types, so Nuke never leaks into TurboImage's
//     public surface (RFC "avoid exposing Nuke types").
//
// Swapping Nuke for another loader means providing a different
// `TIImageLoading` implementation and registering it with
// `TIImageLoaderRegistry`; nothing else changes (RFC rule 1).
//
// Headers in this directory are the *only* public headers of the iOS
// module. Keep them free of C++ so the module stays importable from Swift.

#import <UIKit/UIKit.h>

#import "TIImageRequest.h"

NS_ASSUME_NONNULL_BEGIN

/// Handle for one in-flight load. Cancelling must be idempotent and safe to
/// call after completion.
@protocol TIImageLoadTask <NSObject>
- (void)cancel;
@end

/// Error domain every adapter must report failures in. Codes mirror
/// `turboimage::LoadErrorCode` (cpp/include/turboimage/ImageRequest.h); the
/// integer values are a pinned ABI.
FOUNDATION_EXPORT NSErrorDomain const TIImageLoadErrorDomain;

typedef NS_ERROR_ENUM(TIImageLoadErrorDomain, TIImageLoadErrorCode){
    TIImageLoadErrorUnknown = 0,
    TIImageLoadErrorInvalidRequest = 1,
    TIImageLoadErrorNotCached = 2,
    TIImageLoadErrorNetwork = 3,
    TIImageLoadErrorDecode = 4,
};

/// Completion contract: called exactly once, on the main thread, unless the
/// task was cancelled first (then it may not be called at all). A non-nil
/// error is always in `TIImageLoadErrorDomain`; adapters classify their
/// loader's errors so JS sees the same code on both platforms.
/// `fromMemoryCache` lets the view skip the fade for memory hits, which is
/// what Coil's crossfade does on Android.
///
/// `image` is always a still: for an animated image, its first frame. What
/// plays it is `animation`, which is nil for everything else. It is opaque
/// here because how an animation is played is the loader's business (Nuke:
/// frames decoded lazily into a shared pool). The view only hands it back,
/// to `displayImage:animation:inImageView:` of the loader it came from.
typedef void (^TIImageLoadCompletion)(UIImage *_Nullable image,
                                      id _Nullable animation,
                                      BOOL fromMemoryCache,
                                      NSError *_Nullable error);

/// Progress contract: bytes received / expected (`total` <= 0 if unknown).
/// Called on the main thread, zero or more times, only before completion and
/// never after cancel. Unthrottled: the view applies the core's
/// `ProgressThrottle` so both platforms emit the same event cadence.
typedef void (^TIImageLoadProgress)(int64_t completed, int64_t total);

@protocol TIImageLoading <NSObject>
- (id<TIImageLoadTask>)loadImageWithRequest:(TIImageRequest *)request
                                   progress:(nullable TIImageLoadProgress)progress
                                 completion:(TIImageLoadCompletion)completion;

// Display. The view owns what is on screen and when (the core's lifecycle
// decides); the loader only supplies the image view and plays animations in
// it, because an animation needs a player and a plain UIImageView has none.
// The Android seam goes further and hands the adapter the whole display
// (ADR 0004); here it is only these two calls.

/// A new image view for one TurboImage view. Any UIImageView will do for a
/// loader that plays no animations. Main thread.
///
/// The view sets placeholders and clears the image through `image`, so
/// setting `image` must stop an animation that is playing, as it does for
/// UIImageView's own animated images.
- (UIImageView *)makeImageView NS_SWIFT_UI_ACTOR;

/// Shows the result of a load: `image`, and `animation` playing over it if
/// there is one. Both are what this loader's completion delivered. Main
/// thread.
///
/// `imageView` usually comes from `makeImageView`, but not always (the
/// registry's loader can be replaced while views exist), so a view the
/// loader cannot play in must still get the still image.
- (void)displayImage:(UIImage *)image
           animation:(nullable id)animation
         inImageView:(UIImageView *)imageView NS_SWIFT_UI_ACTOR;

// Cache management, backing the TurboImageModule (prefetch/dispose/clear*).
// Every request and key is already resolved by the core
// (`turboimage::ResolvedRequest`), so views and the module agree on keys.

/// Loads `request` into the caches without displaying it. `completion` is
/// called once on the main thread (not at all after cancel). A request whose
/// `memoryCacheWrite` is off (`destination: 'disk'`) is only downloaded:
/// adapters should store the bytes without decoding them.
- (id<TIImageLoadTask>)prefetchRequest:(TIImageRequest *)request
                            completion:(void (^)(BOOL succeeded))completion;

/// Evicts the image `request` names from memory (every processed and sized
/// variant), from the key-addressed disk cache, and from the HTTP cache.
/// Only the request's `cacheKey` and `url` matter; its policy does not.
///
/// Main thread, so it must not do disk I/O in the caller: the entry has to
/// be gone for the next read when this returns, with the files deleted
/// later. That is why it takes no completion block where the Android seam's
/// `remove` takes `onDone`: Coil's disk cache deletes in the calling thread,
/// Nuke's `DataCache` stages the removal and returns.
- (void)removeCachedImageForRequest:(TIImageRequest *)request;

- (void)clearMemoryCache;
/// Empties both disk stores: the key-addressed cache and the HTTP cache.
/// Same threading rule as `removeCachedImageForRequest:`.
- (void)clearDiskCache;

/// Synchronous memory-cache lookup, for the `memoryCacheKey` placeholder.
/// Main thread; must be cheap (no disk I/O).
- (nullable UIImage *)memoryCachedImageForKey:(NSString *)cacheKey;

@optional
/// `TurboImage.getSize`: loads `request` into the caches like
/// `prefetchRequest:`, then reports the image's own size in pixels with its
/// orientation applied, or the error (in `TIImageLoadErrorDomain`) that
/// stopped it. Adapters should read the size from the file's header rather
/// than decode the image. `completion` is called once on the main thread
/// (not at all after cancel).
///
/// Optional so that an adapter written before `getSize` still conforms;
/// without it, `getSize` rejects with `unknown`.
- (id<TIImageLoadTask>)imageSizeForRequest:(TIImageRequest *)request
                                completion:(void (^)(CGSize size, NSError *_Nullable error))completion;
@end

/// Process-wide loader selection. Thread-safe.
@interface TIImageLoaderRegistry : NSObject

/// The loader every TurboImage view uses. Defaults to the bundled Nuke
/// adapter, looked up at runtime (see the .m for why it is not linked
/// directly). Returns nil only if no adapter is linked into the app.
@property(class, atomic, strong, nullable) id<TIImageLoading> sharedLoader;

/// `TurboImage.configureCache`: the cache sizes, in bytes, the default
/// adapter is created with; 0 keeps the adapter's own default. An adapter
/// reads them when it is created, so this only works before any loader
/// exists: NO, and nothing changes, once `sharedLoader` has made or been
/// given one.
+ (BOOL)configureCacheWithMaxDiskSize:(NSInteger)maxDiskSize maxMemoryCost:(NSInteger)maxMemoryCost;
@property(class, atomic, readonly) NSInteger cacheMaxDiskSize;
@property(class, atomic, readonly) NSInteger cacheMaxMemoryCost;

@end

NS_ASSUME_NONNULL_END
