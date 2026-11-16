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
#include <turboimage/Placeholder.h>
#include <turboimage/Progress.h>

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

const std::shared_ptr<const TurboImageViewProps> &defaultViewProps() {
  static const auto defaultProps = std::make_shared<const TurboImageViewProps>();
  return defaultProps;
}

// Wraps premultiplied RGBA from the core in a UIImage. Copies the pixels so
// the UIImage owns its memory independently of the C++ buffer.
UIImage *imageFromRgba(const turboimage::RgbaImage &rgba) {
  NSData *data = [NSData dataWithBytes:rgba.pixels.data() length:rgba.pixels.size()];
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  // sRGB: blurhash/thumbhash operate in sRGB. (1.x used DeviceRGB, which is
  // sRGB on iOS anyway; naming it is explicit.)
  CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGImageRef cgImage = CGImageCreate(
      static_cast<size_t>(rgba.width), static_cast<size_t>(rgba.height), 8, 32,
      static_cast<size_t>(rgba.width) * 4, colorSpace,
      kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast, provider, nullptr,
      true /* interpolate: placeholders are upscaled */, kCGRenderingIntentDefault);
  UIImage *image = cgImage ? [UIImage imageWithCGImage:cgImage] : nil;
  CGImageRelease(cgImage);
  CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(provider);
  return image;
}

}  // namespace

@interface TurboImageComponentView () <RCTTurboImageViewViewProtocol>
@end

@implementation TurboImageComponentView {
  UIImageView *_imageView;
  id<TIImageLoadTask> _task;
  BOOL _needsReload;
  BOOL _needsPlaceholder;
  // True once the loaded image is on screen; a late placeholder must not
  // replace it.
  BOOL _showingFinalImage;
  // Bumped whenever a placeholder decode is started or invalidated, so an
  // older decode finishing late is dropped (1.x had no such guard and could
  // flash a stale placeholder after `source` changed).
  NSUInteger _placeholderGeneration;
  // Per-load progress throttle (core rule shared with Android).
  turboimage::ProgressThrottle _progressThrottle;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<TurboImageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _props = defaultViewProps();

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
  if (oldViewProps.placeholder.blurhash != newViewProps.placeholder.blurhash ||
      oldViewProps.placeholder.thumbhash != newViewProps.placeholder.thumbhash) {
    _needsPlaceholder = YES;
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
    // startLoad clears the view, so the placeholder must be (re)applied.
    _needsPlaceholder = YES;
    [self startLoad];
  }
  if (_needsPlaceholder) {
    _needsPlaceholder = NO;
    [self applyPlaceholder];
  }
}

// Decodes the placeholder off the main thread with the shared C++ core and
// shows it unless the real image (or a newer placeholder) got there first.
- (void)applyPlaceholder {
  const NSUInteger generation = ++_placeholderGeneration;
  if (_showingFinalImage) {
    return;
  }
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  // Copied into the block: props may change before the decode runs.
  const std::string blurhash = props.placeholder.blurhash;
  const std::string thumbhash = props.placeholder.thumbhash;
  if (blurhash.empty() && thumbhash.empty()) {
    return;
  }

  __weak __typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    const auto rgba = turboimage::decodePlaceholder(blurhash, thumbhash);
    UIImage *placeholder = rgba ? imageFromRgba(*rgba) : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      __typeof(self) strongSelf = weakSelf;
      if (strongSelf == nil || placeholder == nil ||
          strongSelf->_placeholderGeneration != generation ||
          strongSelf->_showingFinalImage) {
        return;
      }
      strongSelf->_imageView.image = placeholder;
    });
  });
}

- (void)startLoad {
  // A load still in flight is superseded: tell JS it was cancelled, so every
  // onStart is matched by exactly one onCompletion.
  if (_task != nil) {
    [_task cancel];
    _task = nil;
    [self emitCompletion:@"cancelled"];
  }
  _imageView.image = nil;
  _showingFinalImage = NO;
  _progressThrottle = turboimage::ProgressThrottle{};

  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  const auto result = turboimage::resolveRequest({
      .uri = props.source.uri,
      .cacheKey = props.source.cacheKey.empty()
                      ? std::nullopt
                      : std::optional<std::string>(props.source.cacheKey),
      .cachePolicy = toCorePolicy(props.cachePolicy),
  });
  // Requests the core rejects fail before onStart: no load ever began.
  if (!result.ok()) {
    [self emitFailure:turboimage::LoadErrorCode::InvalidRequest
              message:[NSString stringWithFormat:@"Invalid request (core error %d)",
                                                 static_cast<int>(result.error)]];
    [self emitCompletion:@"completed"];
    return;
  }

  const auto &resolved = *result.request;
  NSURL *url = [NSURL URLWithString:toNSString(resolved.url)];
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (url == nil || loader == nil) {
    [self emitFailure:url == nil ? turboimage::LoadErrorCode::InvalidRequest
                                 : turboimage::LoadErrorCode::Unknown
              message:url == nil ? @"Invalid URL" : @"No TurboImage loader adapter is linked"];
    [self emitCompletion:@"completed"];
    return;
  }

  TIImageRequest *request = [[TIImageRequest alloc] initWithURL:url
                                                       cacheKey:toNSString(resolved.cacheKey)
                                                memoryCacheRead:resolved.memory.read
                                               memoryCacheWrite:resolved.memory.write
                                                  diskCacheRead:resolved.disk.read
                                                 diskCacheWrite:resolved.disk.write
                                                   allowNetwork:resolved.allowNetwork];
  NSString *source = url.absoluteString;

  [self emitStart];

  // The adapter drops callbacks after cancel, but guard by identity as well:
  // if a newer load replaced this one, its callbacks are stale.
  __weak __typeof(self) weakSelf = self;
  __block id<TIImageLoadTask> thisTask = nil;
  thisTask = [loader loadImageWithRequest:request
      progress:^(int64_t completed, int64_t total) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_task != thisTask ||
            !strongSelf->_progressThrottle.shouldReport(completed, total)) {
          return;
        }
        [strongSelf emitProgress:completed total:(total > 0 ? total : -1)];
      }
      completion:^(UIImage *image, NSError *error) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_task != thisTask) {
          return;
        }
        strongSelf->_task = nil;
        if (image != nil) {
          strongSelf->_showingFinalImage = YES;
          strongSelf->_imageView.image = image;
          [strongSelf emitSuccess:image.size source:source];
        } else {
          // The seam guarantees TIImageLoadErrorDomain; anything else is an
          // adapter bug, reported as unknown.
          const auto code = [error.domain isEqualToString:TIImageLoadErrorDomain]
                                ? static_cast<turboimage::LoadErrorCode>(error.code)
                                : turboimage::LoadErrorCode::Unknown;
          [strongSelf emitFailure:code message:error.localizedDescription ?: @"Unknown error"];
        }
        [strongSelf emitCompletion:@"completed"];
      }];
  _task = thisTask;
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  [_task cancel];
  _task = nil;
  _imageView.image = nil;
  _needsReload = NO;
  _needsPlaceholder = NO;
  _showingFinalImage = NO;
  ++_placeholderGeneration;  // drop any decode still in flight
  // Fabric does not reset `_props` on recycle, and remounts a recycled view
  // with `oldProps:nullptr`. updateProps diffs against `_props`, so without
  // this a recycled view given the same source as its previous life would
  // never reload and stay blank (smoke scenario `recycledSameSource`).
  _props = defaultViewProps();
}

#pragma mark - Events

// One accessor so every emitter shares the "no emitter yet" check (events
// fired before mount, or after unmount, are dropped).
- (std::shared_ptr<const TurboImageViewEventEmitter>)emitter {
  return std::static_pointer_cast<const TurboImageViewEventEmitter>(_eventEmitter);
}

- (void)emitStart {
  if (auto emitter = [self emitter]) {
    emitter->onStart({.state = "running"});
  }
}

- (void)emitProgress:(int64_t)completed total:(int64_t)total {
  if (auto emitter = [self emitter]) {
    emitter->onProgress({.completed = static_cast<double>(completed),
                         .total = static_cast<double>(total)});
  }
}

- (void)emitSuccess:(CGSize)size source:(NSString *)source {
  if (auto emitter = [self emitter]) {
    emitter->onSuccess({.width = size.width,
                        .height = size.height,
                        .source = std::string(source.UTF8String ?: "")});
  }
}

- (void)emitFailure:(turboimage::LoadErrorCode)code message:(NSString *)message {
  if (auto emitter = [self emitter]) {
    emitter->onFailure({
        .code = std::string(turboimage::loadErrorCodeName(code)),
        .error = std::string(message.UTF8String ?: ""),
    });
  }
}

- (void)emitCompletion:(NSString *)state {
  if (auto emitter = [self emitter]) {
    emitter->onCompletion({.state = std::string(state.UTF8String)});
  }
}

@end
