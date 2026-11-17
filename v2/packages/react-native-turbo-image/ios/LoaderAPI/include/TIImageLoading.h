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
typedef void (^TIImageLoadCompletion)(UIImage *_Nullable image,
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

// Cache management, backing the TurboImageModule (prefetch/dispose/clear*).
// Every request and key is already resolved by the core
// (`turboimage::ResolvedRequest`), so views and the module agree on keys.

/// Loads `request` into the caches without displaying it. `completion` is
/// called once on the main thread (not at all after cancel).
- (id<TIImageLoadTask>)prefetchRequest:(TIImageRequest *)request
                            completion:(void (^)(BOOL succeeded))completion;

/// Evicts the image `request` names from memory (every processed and sized
/// variant), from the key-addressed disk cache, and from the HTTP cache.
/// Only the request's `cacheKey` and `url` matter; its policy does not.
- (void)removeCachedImageForRequest:(TIImageRequest *)request;

- (void)clearMemoryCache;
/// Empties both disk stores: the key-addressed cache and the HTTP cache.
- (void)clearDiskCache;

/// Synchronous memory-cache lookup, for the `memoryCacheKey` placeholder.
/// Main thread; must be cheap (no disk I/O).
- (nullable UIImage *)memoryCachedImageForKey:(NSString *)cacheKey;
@end

/// Process-wide loader selection. Thread-safe.
@interface TIImageLoaderRegistry : NSObject

/// The loader every TurboImage view uses. Defaults to the bundled Nuke
/// adapter, looked up at runtime (see the .m for why it is not linked
/// directly). Returns nil only if no adapter is linked into the app.
@property(class, atomic, strong, nullable) id<TIImageLoading> sharedLoader;

@end

NS_ASSUME_NONNULL_END
