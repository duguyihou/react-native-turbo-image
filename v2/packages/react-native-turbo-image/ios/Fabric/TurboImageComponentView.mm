// Fabric host view for <TurboImage> on iOS.
//
// Responsibilities, in order:
//   1. Receive codegen props from React.
//   2. Ask the shared C++ core to resolve them into a `ResolvedRequest`
//      (same code Android runs, RFC rule 4).
//   3. Hand the resolved request to whichever `TIImageLoading` adapter is
//      registered (Nuke by default) and display the result.
//
// This file is the *only* place where React Native, the C++ core and the
// loader seam meet. It must not import Nuke.

#import "TurboImageComponentView.h"

#import <react/renderer/components/TurboImageSpec/ComponentDescriptors.h>
#import <react/renderer/components/TurboImageSpec/EventEmitters.h>
#import <react/renderer/components/TurboImageSpec/Props.h>
#import <react/renderer/components/TurboImageSpec/RCTComponentViewHelpers.h>

#include <turboimage/ImageRequest.h>

#import "TIImageLoading.h"

using namespace facebook::react;

namespace {

turboimage::CachePolicy toCorePolicy(TurboImageViewCachePolicy policy) {
  switch (policy) {
    case TurboImageViewCachePolicy::Default:
      return turboimage::CachePolicy::Default;
    case TurboImageViewCachePolicy::MemoryOnly:
      return turboimage::CachePolicy::MemoryOnly;
    case TurboImageViewCachePolicy::NoCache:
      return turboimage::CachePolicy::NoCache;
    case TurboImageViewCachePolicy::CacheOnly:
      return turboimage::CachePolicy::CacheOnly;
  }
}

UIViewContentMode toContentMode(TurboImageViewResizeMode mode) {
  switch (mode) {
    case TurboImageViewResizeMode::Cover:
      return UIViewContentModeScaleAspectFill;
    case TurboImageViewResizeMode::Contain:
      return UIViewContentModeScaleAspectFit;
    case TurboImageViewResizeMode::Stretch:
      return UIViewContentModeScaleToFill;
    case TurboImageViewResizeMode::Center:
      return UIViewContentModeCenter;
  }
}

NSString *toNSString(const std::string &s) {
  return [[NSString alloc] initWithBytes:s.data()
                                  length:s.size()
                                encoding:NSUTF8StringEncoding];
}

}  // namespace

@interface TurboImageComponentView () <RCTTurboImageViewViewProtocol>
@end

@implementation TurboImageComponentView {
  UIImageView *_imageView;
  id<TIImageLoadTask> _task;
  BOOL _needsReload;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<TurboImageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    static const auto defaultProps = std::make_shared<const TurboImageViewProps>();
    _props = defaultProps;

    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.clipsToBounds = YES;
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.contentView = _imageView;
  }
  return self;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps {
  const auto &oldViewProps = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  const auto &newViewProps = *std::static_pointer_cast<const TurboImageViewProps>(props);

  if (oldViewProps.source.uri != newViewProps.source.uri ||
      oldViewProps.source.cacheKey != newViewProps.source.cacheKey ||
      oldViewProps.cachePolicy != newViewProps.cachePolicy) {
    _needsReload = YES;
  }
  if (oldViewProps.resizeMode != newViewProps.resizeMode) {
    _imageView.contentMode = toContentMode(newViewProps.resizeMode);
  }

  [super updateProps:props oldProps:oldProps];
}

// Loading is deferred to finalizeUpdates so a single transaction that
// changes several request props starts exactly one load.
- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask {
  [super finalizeUpdates:updateMask];
  if (_needsReload) {
    _needsReload = NO;
    [self startLoad];
  }
}

- (void)startLoad {
  [_task cancel];
  _task = nil;
  _imageView.image = nil;

  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  const auto result = turboimage::resolveRequest({
      .uri = props.source.uri,
      .cacheKey = props.source.cacheKey.empty()
                      ? std::nullopt
                      : std::optional<std::string>(props.source.cacheKey),
      .cachePolicy = toCorePolicy(props.cachePolicy),
  });
  if (!result.ok()) {
    [self emitError:[NSString stringWithFormat:@"Invalid request (core error %d)",
                                               static_cast<int>(result.error)]];
    return;
  }

  const auto &resolved = *result.request;
  NSURL *url = [NSURL URLWithString:toNSString(resolved.url)];
  if (url == nil) {
    [self emitError:@"Invalid URL"];
    return;
  }

  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (loader == nil) {
    [self emitError:@"No TurboImage loader adapter is linked"];
    return;
  }

  TIImageRequest *request = [[TIImageRequest alloc] initWithURL:url
                                                       cacheKey:toNSString(resolved.cacheKey)
                                                memoryCacheRead:resolved.memory.read
                                               memoryCacheWrite:resolved.memory.write
                                                  diskCacheRead:resolved.disk.read
                                                 diskCacheWrite:resolved.disk.write
                                                   allowNetwork:resolved.allowNetwork];

  // The adapter drops completions after cancel, but guard by identity as
  // well: if a newer load replaced this one, its result is stale.
  __weak __typeof(self) weakSelf = self;
  __block id<TIImageLoadTask> thisTask = nil;
  thisTask = [loader loadImageWithRequest:request
                               completion:^(UIImage *image, NSError *error) {
                                 __typeof(self) strongSelf = weakSelf;
                                 if (strongSelf == nil || strongSelf->_task != thisTask) {
                                   return;
                                 }
                                 strongSelf->_task = nil;
                                 if (image != nil) {
                                   strongSelf->_imageView.image = image;
                                   [strongSelf emitLoad:image.size];
                                 } else {
                                   [strongSelf emitError:error.localizedDescription ?: @"Unknown error"];
                                 }
                               }];
  _task = thisTask;
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  [_task cancel];
  _task = nil;
  _imageView.image = nil;
  _needsReload = NO;
}

#pragma mark - Events

- (void)emitLoad:(CGSize)size {
  if (auto emitter = std::static_pointer_cast<const TurboImageViewEventEmitter>(_eventEmitter)) {
    emitter->onLoad({.width = size.width, .height = size.height});
  }
}

- (void)emitError:(NSString *)message {
  if (auto emitter = std::static_pointer_cast<const TurboImageViewEventEmitter>(_eventEmitter)) {
    emitter->onError({.message = std::string(message.UTF8String ?: "")});
  }
}

@end
