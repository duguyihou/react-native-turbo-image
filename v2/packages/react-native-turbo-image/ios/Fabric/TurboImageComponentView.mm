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

#import <React/RCTUtils.h>
#import <react/renderer/components/TurboImageSpec/ComponentDescriptors.h>
#import <react/renderer/components/TurboImageSpec/EventEmitters.h>
#import <react/renderer/components/TurboImageSpec/Props.h>
#import <react/renderer/components/TurboImageSpec/RCTComponentViewHelpers.h>

#include <turboimage/ImageRequest.h>
#include <turboimage/Placeholder.h>
#include <turboimage/Progress.h>

#import "TIImageLoading.h"
#import "TIRequestFactory.h"

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


// RN's colour as the core's 0xAARRGGBB, or nullopt when the prop is unset.
std::optional<std::uint32_t> toArgb(const SharedColor &color) {
  if (!color) {
    return std::nullopt;
  }
  return (static_cast<std::uint32_t>(alphaFromColor(color)) << 24) |
         (static_cast<std::uint32_t>(redFromColor(color)) << 16) |
         (static_cast<std::uint32_t>(greenFromColor(color)) << 8) |
         static_cast<std::uint32_t>(blueFromColor(color));
}

turboimage::ProcessingOptions toProcessing(const TurboImageViewProps &props) {
  return {
      .resize = props.resize,
      .blur = props.blur,
      .monochrome = toArgb(props.monochrome),
      .tint = toArgb(props.tint),
  };
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
  // The current load failed; with showPlaceholderOnFailure=false no
  // placeholder may appear any more (even one whose decode finishes later).
  BOOL _loadFailed;
  // Bumped whenever a placeholder decode is started or invalidated, so an
  // older decode finishing late is dropped (1.x had no such guard and could
  // flash a stale placeholder after `source` changed).
  NSUInteger _placeholderGeneration;
  // Per-load progress throttle (core rule shared with Android).
  turboimage::ProgressThrottle _progressThrottle;
  // Last Content-Length seen this load, for the throttle's finish() step.
  int64_t _lastProgressTotal;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<TurboImageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _props = defaultViewProps();

    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.clipsToBounds = YES;
    // Matches the spec default (`contain`, 1.x's default).
    _imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.contentView = _imageView;
  }
  return self;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps {
  const auto &oldViewProps = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  const auto &newViewProps = *std::static_pointer_cast<const TurboImageViewProps>(props);

  if (oldViewProps.source.uri != newViewProps.source.uri ||
      oldViewProps.source.cacheKey != newViewProps.source.cacheKey ||
      oldViewProps.cachePolicy != newViewProps.cachePolicy ||
      // Processors change the pixels, so they need a new load (served from
      // the disk original, or memory if this variant is cached).
      toProcessing(oldViewProps) != toProcessing(newViewProps)) {
    _needsReload = YES;
  }
  if (oldViewProps.placeholder.blurhash != newViewProps.placeholder.blurhash ||
      oldViewProps.placeholder.thumbhash != newViewProps.placeholder.thumbhash ||
      oldViewProps.placeholder.memoryCacheKey != newViewProps.placeholder.memoryCacheKey) {
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
- (BOOL)placeholderAllowed {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  return !_showingFinalImage && !(_loadFailed && !props.showPlaceholderOnFailure);
}

- (void)applyPlaceholder {
  const NSUInteger generation = ++_placeholderGeneration;
  if (![self placeholderAllowed]) {
    return;
  }
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  // memoryCacheKey: a synchronous memory-cache lookup (no decode, no disk),
  // keyed through the core's canonical form exactly like a source.
  if (!props.placeholder.memoryCacheKey.empty()) {
    NSString *key = TIStringFromStd(turboimage::canonicalCacheKey(props.placeholder.memoryCacheKey));
    UIImage *cached = [TIImageLoaderRegistry.sharedLoader memoryCachedImageForKey:key];
    if (cached != nil) {
      _imageView.image = cached;
    }
    return;
  }

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
          strongSelf->_placeholderGeneration != generation || ![strongSelf placeholderAllowed]) {
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
  _loadFailed = NO;
  _progressThrottle = turboimage::ProgressThrottle{};
  _lastProgressTotal = -1;

  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  // Same factory as the cache module, so prefetched keys always match.
  // Fabric applies props (and so starts loads) before mounting, when there
  // is no window to ask; RN's own screen scale is what `PixelRatio` reports
  // to JS, so `resize` means the same here as in the app's layout maths.
  const CGFloat pixelRatio = RCTScreenScale();
  const auto built = TIMakeImageRequest(props.source.uri, props.source.cacheKey,
                                        toCorePolicy(props.cachePolicy), toProcessing(props),
                                        pixelRatio);
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  // Requests the core rejects fail before onStart: no load ever began.
  if (built.request == nil || loader == nil) {
    [self emitFailure:built.request == nil ? built.error : turboimage::LoadErrorCode::Unknown
              message:built.request == nil ? built.message
                                           : @"No TurboImage loader adapter is linked"];
    [self applyFailureToPlaceholder];
    [self emitCompletion:@"completed"];
    return;
  }
  TIImageRequest *request = built.request;
  NSString *source = request.url.absoluteString;

  [self emitStart];

  // The adapter drops callbacks after cancel, but guard by identity as well:
  // if a newer load replaced this one, its callbacks are stale.
  __weak __typeof(self) weakSelf = self;
  __block id<TIImageLoadTask> thisTask = nil;
  thisTask = [loader loadImageWithRequest:request
      progress:^(int64_t completed, int64_t total) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_task != thisTask) {
          return;
        }
        strongSelf->_lastProgressTotal = total;
        if (!strongSelf->_progressThrottle.shouldReport(completed, total)) {
          return;
        }
        [strongSelf emitProgress:completed total:(total > 0 ? total : -1)];
      }
      completion:^(UIImage *image, BOOL fromMemoryCache, NSError *error) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_task != thisTask) {
          return;
        }
        strongSelf->_task = nil;
        if (image != nil) {
          strongSelf->_showingFinalImage = YES;
          // A successful load ends progress at 100% (core rule, see finish()).
          const int64_t total = strongSelf->_lastProgressTotal;
          if (strongSelf->_progressThrottle.finish(total)) {
            [strongSelf emitProgress:total total:total];
          }
          [strongSelf showFinalImage:image animated:!fromMemoryCache];
          [strongSelf emitSuccess:image.size source:source];
        } else {
          [strongSelf applyFailureToPlaceholder];
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

// Cross-fades from whatever is shown (placeholder or blank). Memory-cache
// hits appear instantly, the same rule as Coil's crossfade on Android, so
// scrolling back through a list does not re-fade every cell.
- (void)showFinalImage:(UIImage *)image animated:(BOOL)animated {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  if (!animated || props.fadeDuration <= 0) {
    _imageView.image = image;
    return;
  }
  [UIView transitionWithView:_imageView
                    duration:props.fadeDuration / 1000.0
                     options:UIViewAnimationOptionTransitionCrossDissolve |
                             UIViewAnimationOptionAllowUserInteraction
                  animations:^{
                    self->_imageView.image = image;
                  }
                  completion:nil];
}

// 1.x semantics: without `showPlaceholderOnFailure` the placeholder is
// removed when the load fails. Also stops a placeholder decode still in
// flight from appearing after the failure.
- (void)applyFailureToPlaceholder {
  _loadFailed = YES;
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  if (!props.showPlaceholderOnFailure) {
    ++_placeholderGeneration;
    _imageView.image = nil;
  }
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  [_task cancel];
  _task = nil;
  _imageView.image = nil;
  _needsReload = NO;
  _needsPlaceholder = NO;
  _showingFinalImage = NO;
  _loadFailed = NO;
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
