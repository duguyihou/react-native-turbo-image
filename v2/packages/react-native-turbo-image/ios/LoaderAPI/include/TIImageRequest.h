#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Turns a decoded image into its processed variant, or nil if it cannot.
/// Pure and thread-safe; adapters call it on their decode/processing queue,
/// never on the main thread.
typedef UIImage *_Nullable (^TIImageProcessor)(UIImage *image);

/// An already-resolved request, produced from `turboimage::ResolvedRequest`
/// by the Fabric layer. Adapters translate these fields mechanically and
/// must not re-derive cache keys or policies themselves: the C++ core is the
/// single owner of those semantics (RFC rule 2).
///
/// Immutable, therefore safe to pass across threads.
@interface TIImageRequest : NSObject

@property(nonatomic, readonly, copy) NSURL *url;
/// Key to use for both memory and disk caches.
@property(nonatomic, readonly, copy) NSString *cacheKey;
@property(nonatomic, readonly) BOOL memoryCacheRead;
@property(nonatomic, readonly) BOOL memoryCacheWrite;
@property(nonatomic, readonly) BOOL diskCacheRead;
@property(nonatomic, readonly) BOOL diskCacheWrite;
@property(nonatomic, readonly) BOOL allowNetwork;
/// Identity of `processor`, or empty when there is none. `cacheKey` names the
/// original; adapters must fold this into their *memory* key so each variant
/// is cached separately, while the disk tier keeps one original.
@property(nonatomic, readonly, copy) NSString *processorKey;
/// Applies the processors the key describes. nil iff `processorKey` is empty.
/// The core owns the algorithms; adapters only schedule this step.
@property(nonatomic, readonly, copy, nullable) TIImageProcessor processor;

- (instancetype)initWithURL:(NSURL *)url
                   cacheKey:(NSString *)cacheKey
            memoryCacheRead:(BOOL)memoryCacheRead
           memoryCacheWrite:(BOOL)memoryCacheWrite
              diskCacheRead:(BOOL)diskCacheRead
             diskCacheWrite:(BOOL)diskCacheWrite
               allowNetwork:(BOOL)allowNetwork
               processorKey:(NSString *)processorKey
                  processor:(nullable TIImageProcessor)processor NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
