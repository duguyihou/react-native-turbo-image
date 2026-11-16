#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

- (instancetype)initWithURL:(NSURL *)url
                   cacheKey:(NSString *)cacheKey
            memoryCacheRead:(BOOL)memoryCacheRead
           memoryCacheWrite:(BOOL)memoryCacheWrite
              diskCacheRead:(BOOL)diskCacheRead
             diskCacheWrite:(BOOL)diskCacheWrite
               allowNetwork:(BOOL)allowNetwork NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
