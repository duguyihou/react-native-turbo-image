#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns the processed image, or nil. Pure and thread-safe; called off the
/// main thread.
typedef UIImage *_Nullable (^TIImageProcessor)(UIImage *image);

/// A request already resolved by the C++ core. Adapters map fields as-is and
/// never re-derive keys or policies (RFC rule 2): a memory key may add
/// `processorKey` and the vector size it resolved, but names what the core
/// named. Immutable.
@interface TIImageRequest : NSObject

@property(nonatomic, readonly, copy) NSURL *url;
/// The image both cache tiers key by; the memory tier adds the variant.
@property(nonatomic, readonly, copy) NSString *cacheKey;
@property(nonatomic, readonly) BOOL memoryCacheRead;
@property(nonatomic, readonly) BOOL memoryCacheWrite;
@property(nonatomic, readonly) BOOL diskCacheRead;
@property(nonatomic, readonly) BOOL diskCacheWrite;
@property(nonatomic, readonly) BOOL allowNetwork;
/// Identity of `processor`, or empty. Fold it into the memory key only; disk
/// keeps one original.
@property(nonatomic, readonly, copy) NSString *processorKey;
/// nil iff `processorKey` is empty. Adapters only schedule it.
@property(nonatomic, readonly, copy, nullable) TIImageProcessor processor;
/// Validated `@[name, value]` pairs, in order; repeated names are all sent.
/// Not part of any cache key.
@property(nonatomic, readonly, copy) NSArray<NSArray<NSString *> *> *headers;
/// YES for `cachePolicy="urlCache"`: the disk tier is a separate HTTP cache
/// keyed by `url` that obeys `Cache-Control`; the `cacheKey` disk cache is
/// not touched. `cacheKey` still keys memory.
@property(nonatomic, readonly) BOOL httpCache;
/// Max decode size in pixels, without allocating the full bitmap; never
/// upscales, keeps aspect. Zero: original. Zero height: width only.
@property(nonatomic, readonly) CGSize decodeSize;
/// YES: aspect fill `decodeSize`; NO: aspect fit. Needs both dimensions.
@property(nonatomic, readonly) BOOL decodeFill;
/// Pixel size to rasterize a vector image (SVG) at before `processor` runs:
/// a target, not a bound. Zero: own size times `displayScale`. Differs from
/// `decodeSize` because a vector is drawn for the view even without
/// downscaling. Unused without a `processor`.
@property(nonatomic, readonly) CGSize vectorDecodeSize;
@property(nonatomic, readonly) BOOL vectorDecodeFill;
/// Pixels per point of the screen the image is for.
@property(nonatomic, readonly) CGFloat displayScale;

- (instancetype)initWithURL:(NSURL *)url
                   cacheKey:(NSString *)cacheKey
            memoryCacheRead:(BOOL)memoryCacheRead
           memoryCacheWrite:(BOOL)memoryCacheWrite
              diskCacheRead:(BOOL)diskCacheRead
             diskCacheWrite:(BOOL)diskCacheWrite
               allowNetwork:(BOOL)allowNetwork
               processorKey:(NSString *)processorKey
                  processor:(nullable TIImageProcessor)processor
                    headers:(NSArray<NSArray<NSString *> *> *)headers
                  httpCache:(BOOL)httpCache
                 decodeSize:(CGSize)decodeSize
                 decodeFill:(BOOL)decodeFill
           vectorDecodeSize:(CGSize)vectorDecodeSize
           vectorDecodeFill:(BOOL)vectorDecodeFill
               displayScale:(CGFloat)displayScale NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
