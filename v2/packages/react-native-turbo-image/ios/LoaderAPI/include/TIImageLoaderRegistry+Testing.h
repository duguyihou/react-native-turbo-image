// For tests only: lets them swap the loader (ADR 0014).

#import "TIImageLoading.h"

NS_ASSUME_NONNULL_BEGIN

@interface TIImageLoaderRegistry (Testing)

/// Replaces `sharedLoader`; nil restores the bundled adapter.
+ (void)setSharedLoaderForTesting:(nullable id<TIImageLoading>)loader;

@end

NS_ASSUME_NONNULL_END
