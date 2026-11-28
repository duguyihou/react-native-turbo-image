// Fabric host view for <TurboImage> on iOS: props -> core request -> loader
// seam -> display. The core's `ViewLifecycle` decides what shows and which
// events fire; this view carries out its effects (`perform:step:`).
// The only place RN, the core and the seam meet. Never import Nuke here.

#import "TurboImageComponentView.h"

#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <react/renderer/components/TurboImageSpec/ComponentDescriptors.h>
#import <react/renderer/components/TurboImageSpec/EventEmitters.h>
#import <react/renderer/components/TurboImageSpec/Props.h>
#import <react/renderer/components/TurboImageSpec/RCTComponentViewHelpers.h>

#include <turboimage/ImageRequest.h>
#include <turboimage/Placeholder.h>
#include <turboimage/Progress.h>
#include <turboimage/ViewLifecycle.h>

#import "TIImageLoading.h"
#import "TILiveText.h"
#import "TIRequestFactory.h"

using namespace facebook::react;

namespace {

// The seam's codes are cast to the core's, so they must match exactly.
#define TI_ASSERT_SAME_CODE(seam, core)                                              \
  static_assert(static_cast<int>(seam) == static_cast<int>(turboimage::LoadErrorCode::core), \
                "TIImageLoadErrorCode and turboimage::LoadErrorCode disagree")
TI_ASSERT_SAME_CODE(TIImageLoadErrorUnknown, Unknown);
TI_ASSERT_SAME_CODE(TIImageLoadErrorInvalidRequest, InvalidRequest);
TI_ASSERT_SAME_CODE(TIImageLoadErrorNotCached, NotCached);
TI_ASSERT_SAME_CODE(TIImageLoadErrorNetwork, Network);
TI_ASSERT_SAME_CODE(TIImageLoadErrorDecode, Decode);
TI_ASSERT_SAME_CODE(TIImageLoadErrorHttp, Http);
#undef TI_ASSERT_SAME_CODE

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
    case TurboImageViewCachePolicy::UrlCache:
      return turboimage::CachePolicy::UrlCache;
  }
}

turboimage::ResizeMode toCoreResizeMode(TurboImageViewResizeMode mode) {
  switch (mode) {
    case TurboImageViewResizeMode::Cover:
      return turboimage::ResizeMode::Cover;
    case TurboImageViewResizeMode::Contain:
      return turboimage::ResizeMode::Contain;
    case TurboImageViewResizeMode::Stretch:
      return turboimage::ResizeMode::Stretch;
    case TurboImageViewResizeMode::Center:
      return turboimage::ResizeMode::Center;
    case TurboImageViewResizeMode::ScaleDown:
      return turboimage::ResizeMode::ScaleDown;
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
    case TurboImageViewResizeMode::ScaleDown:
      // placeImage handles it; fit until there is an image.
      return UIViewContentModeScaleAspectFit;
  }
}


// RN colour as 0xAARRGGBB, or nullopt if unset.
std::optional<std::uint32_t> toArgb(const SharedColor &color) {
  if (!color) {
    return std::nullopt;
  }
  return (static_cast<std::uint32_t>(alphaFromColor(color)) << 24) |
         (static_cast<std::uint32_t>(redFromColor(color)) << 16) |
         (static_cast<std::uint32_t>(greenFromColor(color)) << 8) |
         static_cast<std::uint32_t>(blueFromColor(color));
}

// Codegen header structs have no operator==, so compare after converting.
std::vector<turboimage::Header> toHeaders(const TurboImageViewSourceStruct &source) {
  std::vector<turboimage::Header> headers;
  headers.reserve(source.headers.size());
  for (const auto &header : source.headers) {
    headers.push_back({.name = header.name, .value = header.value});
  }
  return headers;
}

turboimage::ProcessingOptions toProcessing(const TurboImageViewProps &props) {
  return {
      .resize = props.resize,
      .blur = props.blur,
      .monochrome = toArgb(props.monochrome),
      .tint = toArgb(props.tint),
  };
}

// Redbox in development; in production the effect is just skipped.
void TIUnexpectedEffect(NSString *kind) {
  RCTLogError(@"TurboImage: the lifecycle sent %@ from a step that cannot produce it", kind);
}

const std::shared_ptr<const TurboImageViewProps> &defaultViewProps() {
  static const auto defaultProps = std::make_shared<const TurboImageViewProps>();
  return defaultProps;
}

// Core RGBA to UIImage, copying the pixels.
UIImage *imageFromRgba(const turboimage::RgbaImage &rgba) {
  NSData *data = [NSData dataWithBytes:rgba.pixels.data() length:rgba.pixels.size()];
  CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
  // blurhash/thumbhash are sRGB.
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

// Step-specific effects, as blocks closing over what the step knows. A nil
// block means the lifecycle sent an effect its step can't produce: a bug,
// reported and skipped.
struct TIStepEffects {
  void (^deliverInvalidRequest)(void) = nil;
  void (^startLoad)(int64_t token) = nil;
  void (^deliverSuccess)(void) = nil;
  void (^deliverFailure)(void) = nil;
};

// Clips to the content box and holds the image view, whose frame
// `placeImage` sets (UIKit modes can't combine scale with `contentPosition`).
// Re-places the image on every layout.
@interface TIImageContainer : UIView
@property(nonatomic, copy, nullable) void (^onLayout)(void);
@end

@implementation TIImageContainer
- (void)layoutSubviews {
  [super layoutSubviews];
  if (_onLayout != nil) {
    _onLayout();
  }
}
@end

@interface TurboImageComponentView () <RCTTurboImageViewViewProtocol>
@end

@implementation TurboImageComponentView {
  UIImageView *_imageView;
  TIImageContainer *_container;
  // Decides what shows and which events fire (shared with Android).
  turboimage::ViewLifecycle _lifecycle;
  // Cancels the load in flight; nil when there is none.
  id<TIImageLoadTask> _task;
  // Set by updateProps, consumed by finalizeUpdates.
  BOOL _propsChanged;
  // The current load's request; empty before the first load and after recycle.
  std::optional<turboimage::ImageRequest> _loadedRequest;
  BOOL _needsPlaceholder;
  // `showPlaceholderOnFailure` changed; ignored when `_needsPlaceholder`
  // re-applies anyway.
  BOOL _showPlaceholderOnFailureChanged;
  BOOL _needsLiveTextUpdate;
  // `recyclingKey` changed: the next load must not keep the previous image.
  BOOL _recyclingKeyChanged;
  // Per-load progress throttle (shared with Android).
  turboimage::ProgressThrottle _progressThrottle;
  // Last total seen this load, for the throttle's finish().
  int64_t _lastProgressTotal;
  // Created on first use; nil while Live Text is off or unsupported.
  id<TILiveTextInteraction> _liveText;
  // Set by prepareForRecycle: compare the next props with defaults.
  BOOL _recycled;
  // The on-screen image's request if it was decoded for the view size and
  // may need a larger reload when the view grows; nil otherwise. Plus its
  // decoded size and the view size it was loaded for.
  TIImageRequest *_upgradable;
  turboimage::PixelSize _upgradableDecoded;
  turboimage::PixelSize _upgradableLoadedFor;
  // Load for `placeholder.uri`. Never reported to JS; cancelled when moot.
  id<TIImageLoadTask> _placeholderTask;
  // Trips to the background, counted by this view. A load that fails with
  // `network` after one was likely cut off by it (iOS drops connections and
  // reports it on return), so it retries at once (`ViewLifecycle::retry`);
  // any other network failure waits for the next return to the foreground.
  // Signed: a load started in the background records one trip fewer, which
  // is -1 for a view made there.
  NSInteger _backgroundTrips;
  BOOL _inBackground;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<TurboImageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _props = defaultViewProps();

    // The loader's image view (it plays animations); plain if none is linked.
    _imageView = [TIImageLoaderRegistry.sharedLoader makeImageView] ?: [UIImageView new];
    _imageView.clipsToBounds = YES;
    // Read from the default props so it can't drift from the spec.
    _imageView.contentMode = toContentMode(defaultViewProps()->resizeMode);
    _container = [[TIImageContainer alloc] initWithFrame:self.bounds];
    _container.clipsToBounds = YES;
    _imageView.frame = _container.bounds;
    [_container addSubview:_imageView];
    __weak __typeof(self) weakSelf = self;
    _container.onLayout = ^{
      [weakSelf placeImage];
    };
    self.contentView = _container;

    // A view made while the app is already in the background (data that
    // arrived after the user left) is in the background from the start, so
    // a load it starts then counts as possibly cut by this trip. Nil in an
    // app extension, which reads as active.
    _inBackground = RCTSharedApplication().applicationState == UIApplicationStateBackground;
    // UIApplication-level, so scene-based apps get them too. Removed on
    // dealloc by NSNotificationCenter itself; a recycled view keeps them and
    // has nothing to retry.
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self
               selector:@selector(appDidEnterBackground)
                   name:UIApplicationDidEnterBackgroundNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(appWillEnterForeground)
                   name:UIApplicationWillEnterForegroundNotification
                 object:nil];
  }
  return self;
}

#pragma mark - Retry

- (void)appDidEnterBackground {
  _inBackground = YES;
  ++_backgroundTrips;
}

- (void)appWillEnterForeground {
  _inBackground = NO;
  [self retryFailedLoad];
}

// The failed load again, if the core allows it (a network failure, nothing
// since), as a new load with its own events.
- (void)retryFailedLoad {
  if (_lifecycle.retryable == 0 || !_loadedRequest.has_value() ||
      TIImageLoaderRegistry.sharedLoader == nil) {
    return;
  }
  TIRequestResult built = [self makeRequest:*_loadedRequest];
  if (built.request == nil) {
    return;
  }
  _progressThrottle = turboimage::ProgressThrottle{};
  _lastProgressTotal = -1;
  TIImageRequest *request = built.request;
  TIStepEffects step;
  step.startLoad = ^(int64_t token) {
    [self startLoad:request token:token];
  };
  [self perform:_lifecycle.retry([self lifecycleProps]) step:step];
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps {
  // After a recycle Fabric keeps the old `_props` (the base class diffs
  // against them), but our state was reset, so diff against the defaults.
  // Otherwise a recycled view could miss its placeholder or Live Text.
  const auto &oldViewProps =
      *std::static_pointer_cast<const TurboImageViewProps>(_recycled ? defaultViewProps() : _props);
  const auto &newViewProps = *std::static_pointer_cast<const TurboImageViewProps>(props);
  _recycled = NO;

  // finalizeUpdates compares the whole request once `_props` is updated.
  _propsChanged = YES;
  // Not a request prop: only affects a load started in this transaction.
  if (oldViewProps.recyclingKey != newViewProps.recyclingKey) {
    _recyclingKeyChanged = YES;
  }
  // Placeholder changes alone start no reload.
  if (oldViewProps.placeholder.blurhash != newViewProps.placeholder.blurhash ||
      oldViewProps.placeholder.thumbhash != newViewProps.placeholder.thumbhash ||
      oldViewProps.placeholder.memoryCacheKey != newViewProps.placeholder.memoryCacheKey ||
      oldViewProps.placeholder.uri != newViewProps.placeholder.uri) {
    _needsPlaceholder = YES;
  }
  // Decides only what a failure shows; the core redoes nothing elsewhere.
  if (oldViewProps.showPlaceholderOnFailure != newViewProps.showPlaceholderOnFailure) {
    _showPlaceholderOnFailureChanged = YES;
  }
  if (oldViewProps.enableLiveTextInteraction != newViewProps.enableLiveTextInteraction) {
    // Applied in finalizeUpdates, once `_props` holds the new value.
    _needsLiveTextUpdate = YES;
  }
  // resizeMode and contentPosition: applied by placeImage in finalizeUpdates.

  [super updateProps:props oldProps:oldProps];
}

// Deferred here so one transaction starts at most one load.
- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask {
  [super finalizeUpdates:updateMask];
  [self placeImage];
  if (_propsChanged) {
    _propsChanged = NO;
    // Load when the core request changed, and always on first props (so a
    // missing source reports `invalidRequest`). Comparing the whole request
    // means no new field can be forgotten.
    auto request = [self coreRequest];
    if (!_loadedRequest.has_value() || *_loadedRequest != request) {
      _loadedRequest = std::move(request);
      // A reload may clear the view, so reapply the placeholder.
      _needsPlaceholder = YES;
      [self reload];
    }
  }
  // Only applies to a load in its own transaction.
  _recyclingKeyChanged = NO;
  if (_needsPlaceholder) {
    _needsPlaceholder = NO;
    [self perform:_lifecycle.applyPlaceholder([self lifecycleProps]) step:TIStepEffects{}];
  } else if (_showPlaceholderOnFailureChanged) {
    [self perform:_lifecycle.showPlaceholderOnFailureChanged([self lifecycleProps])
             step:TIStepEffects{}];
  }
  _showPlaceholderOnFailureChanged = NO;
  if (_needsLiveTextUpdate) {
    _needsLiveTextUpdate = NO;
    [self updateLiveText];
  }
}

#pragma mark - Live Text

// Analyses only the loaded image, never a placeholder.
- (void)updateLiveText {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  if (!props.enableLiveTextInteraction) {
    [_liveText detach];
    _liveText = nil;
    return;
  }
  if (_lifecycle.showingState() != turboimage::Showing::LoadedImage || _imageView.image == nil) {
    return;  // the load's success calls this again
  }
  if (_liveText == nil) {
    _liveText = TIMakeLiveTextInteraction();
  }
  [_liveText analyzeImage:_imageView.image inImageView:_imageView];
}

#pragma mark - Lifecycle

// The props the lifecycle depends on.
- (turboimage::LifecycleProps)lifecycleProps {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  // `memoryCacheKey` wins if several kinds are passed.
  const auto kind = !props.placeholder.memoryCacheKey.empty()
                        ? turboimage::PlaceholderKind::MemoryCacheKey
                        // An image placeholder arrives late, like a hash.
                        : !props.placeholder.blurhash.empty() || !props.placeholder.thumbhash.empty() ||
                                  !props.placeholder.uri.empty()
                              ? turboimage::PlaceholderKind::Hash
                              : turboimage::PlaceholderKind::None;
  return {.placeholder = kind, .showPlaceholderOnFailure = props.showPlaceholderOnFailure};
}

// A request prop changed: resolve it and let the lifecycle swap loads.
- (void)reload {
  // Nothing to upgrade until the new image arrives.
  _upgradable = nil;
  // The old image's analysis must not outlive its request.
  [_liveText detach];
  _progressThrottle = turboimage::ProgressThrottle{};
  _lastProgressTotal = -1;

  // Unstartable requests fail without onStart.
  TIRequestResult built = [self makeRequest:*_loadedRequest];
  if (built.request != nil && TIImageLoaderRegistry.sharedLoader == nil) {
    built = {.request = nil,
             .error = turboimage::LoadErrorCode::Unknown,
             .message = @"No TurboImage loader adapter is linked"};
  }
  TIStepEffects step;
  if (built.request != nil) {
    TIImageRequest *request = built.request;
    step.startLoad = ^(int64_t token) {
      [self startLoad:request token:token];
    };
  } else {
    const auto code = built.error;
    NSString *message = built.message;
    step.deliverInvalidRequest = ^{
      [self emitFailure:code message:message];
    };
  }
  [self perform:_lifecycle.reload(_recyclingKeyChanged, _imageView.image != nil,
                                  built.request != nil, [self lifecycleProps])
           step:step];
}

// Carries out the lifecycle's effects in order, without second-guessing.
// `step` blocks capture `self` strongly, but run before return: no cycle.
- (void)perform:(const turboimage::LifecycleEffects &)effects step:(const TIStepEffects &)step {
  using Kind = turboimage::LifecycleEffect::Kind;
  for (const auto &effect : effects) {
    switch (effect.kind) {
      case Kind::CancelLoad:
        [_task cancel];
        _task = nil;
        break;
      case Kind::ClearImage:
        _imageView.image = nil;
        [self placeImage];
        break;
      case Kind::EmitCancelled:
        [self emitCompletion:@"cancelled"];
        break;
      case Kind::EmitCompleted:
        [self emitCompletion:@"completed"];
        break;
      case Kind::DeliverInvalidRequest:
        if (step.deliverInvalidRequest != nil) {
          step.deliverInvalidRequest();
        } else {
          TIUnexpectedEffect(@"DeliverInvalidRequest");
        }
        break;
      case Kind::StartLoad:
        if (step.startLoad != nil) {
          step.startLoad(effect.value);
        } else {
          TIUnexpectedEffect(@"StartLoad");
        }
        break;
      case Kind::DeliverSuccess:
        _task = nil;
        if (step.deliverSuccess != nil) {
          step.deliverSuccess();
        } else {
          TIUnexpectedEffect(@"DeliverSuccess");
        }
        break;
      case Kind::DeliverFailure:
        _task = nil;
        if (step.deliverFailure != nil) {
          step.deliverFailure();
        } else {
          TIUnexpectedEffect(@"DeliverFailure");
        }
        break;
      case Kind::ShowCachedPlaceholder:
        [self showCachedPlaceholder];
        break;
      case Kind::DecodePlaceholder:
        [self decodePlaceholder:effect.value];
        break;
    }
  }
}

#pragma mark - Loading

- (void)startLoad:(TIImageRequest *)request token:(int64_t)token {
  NSString *source = request.url.absoluteString;
  // A load started in the background (the app runs briefly after leaving
  // the screen) has not yet survived the trip it started in, so it counts
  // as starting before it: a failure after the return then retries at once.
  const NSInteger tripsAtStart = _backgroundTrips - (_inBackground ? 1 : 0);

  // A local source's I/O failure is not retried (`loadFailed`).
  const bool remoteSource = turboimage::isRemoteSource(request.url.absoluteString.UTF8String);

  [self emitStart];

  // The lifecycle also guards by token, so a stale callback does nothing.
  __weak __typeof(self) weakSelf = self;
  // No progress block without a JS `onProgress` handler.
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  TIImageLoadProgress progress = nil;
  if (props.progressEnabled) {
    progress = ^(int64_t completed, int64_t total) {
      __typeof(self) strongSelf = weakSelf;
      if (strongSelf != nil && strongSelf->_lifecycle.isInFlight(token)) {
        [strongSelf loadDidProgress:completed total:total];
      }
    };
  }
  id<TIImageLoadTask> task = [TIImageLoaderRegistry.sharedLoader loadImageWithRequest:request
      progress:progress
      completion:^(UIImage *image, id animation, BOOL fromMemoryCache, NSError *error) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }
        // nil `image` means failure; `error` says why.
        TIStepEffects step;
        if (image != nil) {
          step.deliverSuccess = ^{
            [strongSelf deliverSuccess:image
                             animation:animation
                       fromMemoryCache:fromMemoryCache
                                source:source];
            [strongSelf cancelPlaceholderLoad];
            [strongSelf rememberImage:image animation:animation request:request];
          };
          [strongSelf perform:strongSelf->_lifecycle.loadSucceeded(token) step:step];
        } else {
          step.deliverFailure = ^{
            [strongSelf deliverFailure:error];
          };
          [strongSelf perform:strongSelf->_lifecycle.loadFailed(token, [strongSelf lifecycleProps],
                                                                TICoreErrorCode(error), remoteSource)
                         step:step];
          // Cut off by a trip to the background and back: retry now. Still
          // in the background: `appWillEnterForeground` retries.
          if (strongSelf->_backgroundTrips != tripsAtStart && !strongSelf->_inBackground) {
            [strongSelf retryFailedLoad];
          }
        }
      }];
  // A memory hit may have completed synchronously; keep the task only if not.
  if (_lifecycle.isInFlight(token)) {
    _task = task;
  }
}

// Same factory as the cache module, so prefetched keys match.
- (TIRequestResult)makeRequest:(const turboimage::ImageRequest &)request {
  const CGFloat pixelRatio = request.pixelRatio;
  // Bounds are already this transaction's (layout precedes finalizeUpdates).
  const CGSize viewPixelSize = CGSizeMake(self.bounds.size.width * pixelRatio,
                                          self.bounds.size.height * pixelRatio);
  return TIMakeImageRequest(request, viewPixelSize);
}

// The view's size in pixels.
- (turboimage::PixelSize)viewPixelSize {
  const CGFloat pixelRatio = RCTScreenScale();
  return {self.bounds.size.width * pixelRatio, self.bounds.size.height * pixelRatio};
}

// The current props as the core's request.
- (turboimage::ImageRequest)coreRequest {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  return {
      .uri = props.source.uri,
      .cacheKey = TIOptionalCacheKey(props.source.cacheKey),
      .cachePolicy = toCorePolicy(props.cachePolicy),
      // Processors change pixels, so they need a new load.
      .processing = toProcessing(props),
      // No window before mount; RN's scale matches JS `PixelRatio`.
      .pixelRatio = RCTScreenScale(),
      .headers = toHeaders(props.source),
      // Both decide the decode size.
      .allowDownscaling = props.allowDownscaling,
      .resizeMode = toCoreResizeMode(props.resizeMode),
  };
}

- (void)loadDidProgress:(int64_t)completed total:(int64_t)total {
  _lastProgressTotal = total;
  if (_progressThrottle.shouldReport(completed, total)) {
    [self emitProgress:completed total:(total > 0 ? total : -1)];
  }
}

- (void)deliverSuccess:(UIImage *)image
             animation:(nullable id)animation
       fromMemoryCache:(BOOL)fromMemoryCache
                source:(NSString *)source {
  // Success ends progress at 100%.
  if (_progressThrottle.finish(_lastProgressTotal)) {
    [self emitProgress:_lastProgressTotal total:_lastProgressTotal];
  }
  [self showFinalImage:image animation:animation fade:!fromMemoryCache];
  [self updateLiveText];
  // In pixels, as on Android.
  const CGFloat scale = image.scale > 0 ? image.scale : 1;
  [self emitSuccess:CGSizeMake(image.size.width * scale, image.size.height * scale)
             source:source];
}

#pragma mark - Upgrades

// A view may outgrow its image when resized after the load.
- (void)updateLayoutMetrics:(const LayoutMetrics &)layoutMetrics
           oldLayoutMetrics:(const LayoutMetrics &)oldLayoutMetrics {
  [super updateLayoutMetrics:layoutMetrics oldLayoutMetrics:oldLayoutMetrics];
  const auto &size = layoutMetrics.frame.size;
  const auto &oldSize = oldLayoutMetrics.frame.size;
  if (size.width > oldSize.width || size.height > oldSize.height) {
    [self upgradeIfOutgrown];
  }
}

// Remembers an image sized for this view, then checks if it's outgrown.
// Skips animations (the player sizes frames; a swap restarts it), vectors,
// and decodes not bounded by the view.
- (void)rememberImage:(UIImage *)image
            animation:(nullable id)animation
              request:(TIImageRequest *)request {
  const CGSize bound = request.decodeSize;
  if (animation != nil || image.CGImage == nil || bound.width <= 0 || bound.height <= 0) {
    _upgradable = nil;
    return;
  }
  _upgradable = request;
  const CGFloat scale = image.scale > 0 ? image.scale : 1;
  _upgradableDecoded = {image.size.width * scale, image.size.height * scale};
  _upgradableLoadedFor = {bound.width, bound.height};
  // The view may have grown while the load ran.
  [self upgradeIfOutgrown];
}

// Reloads at the view's size if it grew past the image. Silent: no events,
// and on failure the current image stays.
- (void)upgradeIfOutgrown {
  if (_upgradable == nil || !_loadedRequest.has_value()) {
    return;
  }
  const turboimage::PixelSize now = [self viewPixelSize];
  if (!turboimage::needsLargerDecode(_upgradableDecoded, _upgradableLoadedFor, now,
                                     _upgradable.decodeFill)) {
    return;
  }
  TIRequestResult built = [self makeRequest:*_loadedRequest];
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (built.request == nil || loader == nil) {
    return;
  }
  const std::int64_t token = _lifecycle.startUpgrade();
  if (token == 0) {
    return;
  }
  TIImageRequest *request = built.request;
  __weak __typeof(self) weakSelf = self;
  id<TIImageLoadTask> task = [loader loadImageWithRequest:request
      progress:nil
      completion:^(UIImage *image, id animation, BOOL /* fromMemoryCache */, NSError *error) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }
        if (image == nil) {
          if (!strongSelf->_lifecycle.isUpgrading(token)) {
            return;
          }
          strongSelf->_lifecycle.upgradeFailed(token);
          strongSelf->_task = nil;
          // Don't retry at this size; a new source or reload starts over.
          strongSelf->_upgradableLoadedFor = now;
          return;
        }
        if (!strongSelf->_lifecycle.upgradeSucceeded(token)) {
          return;  // superseded by a reload, recycle or drop
        }
        strongSelf->_task = nil;
        // No fade: same picture, sharper.
        [loader displayImage:image animation:animation inImageView:strongSelf->_imageView];
        [strongSelf placeImage];
        [strongSelf updateLiveText];
        // Check again in case the view kept growing.
        [strongSelf rememberImage:image animation:animation request:request];
      }];
  // Keep the task only if it didn't complete synchronously.
  if (_lifecycle.isUpgrading(token)) {
    _task = task;
  }
}


- (void)deliverFailure:(NSError *)error {
  [self emitFailure:TICoreErrorCode(error)
            message:error.localizedDescription ?: @"Unknown error"];
}

// Cross-fades from whatever is shown; memory hits appear instantly (like
// Coil). The loader displays it, since it plays animations.
- (void)showFinalImage:(UIImage *)image animation:(nullable id)animation fade:(BOOL)fade {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (!fade || props.fadeDuration <= 0) {
    [loader displayImage:image animation:animation inImageView:_imageView];
    [self placeImage];
    return;
  }
  [UIView transitionWithView:_imageView
                    duration:props.fadeDuration / 1000.0
                     options:UIViewAnimationOptionTransitionCrossDissolve |
                             UIViewAnimationOptionAllowUserInteraction
                  animations:^{
                    [loader displayImage:image animation:animation inImageView:self->_imageView];
                    // Inside the transition so its end state has the new frame.
                    [self placeImage];
                  }
                  completion:nil];
}

#pragma mark - Placeholder

// Lays out the image view for resizeMode and contentPosition. Centred
// cover/contain use UIKit's content mode; otherwise the core's placeImage
// computes the rect, as on Android. Center and scale-down always compute it:
// UIKit would size a scale-1 bitmap in points, not pixels / screen scale.
- (void)placeImage {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  const CGRect box = _container.bounds;
  const BOOL centred = props.contentPositionX == 0.5 && props.contentPositionY == 0.5;
  const BOOL ownSize = props.resizeMode == TurboImageViewResizeMode::Center ||
                       props.resizeMode == TurboImageViewResizeMode::ScaleDown;
  UIImage *image = _imageView.image;
  const BOOL computed = (!centred || ownSize) &&
                        props.resizeMode != TurboImageViewResizeMode::Stretch && image != nil &&
                        image.size.width > 0 && image.size.height > 0;
  if (!computed) {
    _imageView.contentMode = toContentMode(props.resizeMode);
    _imageView.frame = box;
    return;
  }
  const CGFloat screenScale = RCTScreenScale();
  const CGSize points = image.CGImage == nil
                            ? image.size
                            : CGSizeMake(image.size.width * image.scale / screenScale,
                                         image.size.height * image.scale / screenScale);
  const auto placed = turboimage::placeImage(
      {points.width, points.height}, {box.size.width, box.size.height},
      toCoreResizeMode(props.resizeMode),
      {.x = props.contentPositionX, .y = props.contentPositionY});
  _imageView.contentMode = UIViewContentModeScaleToFill;
  _imageView.frame = CGRectMake(placed.x, placed.y, placed.width, placed.height);
}

// Sync memory lookup over the core's candidate keys; a miss clears the view.
- (void)showCachedPlaceholder {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  UIImage *cached = nil;
  for (const auto &key : turboimage::memoryCacheKeyCandidates(props.placeholder.memoryCacheKey)) {
    cached = [loader memoryCachedImageForKey:TIStringFromStd(key)];
    if (cached != nil) {
      break;
    }
  }
  _imageView.image = cached;
  [self placeImage];
}

// Decodes off main; shown only if the lifecycle says it's still current.
- (void)decodePlaceholder:(int64_t)generation {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  if (!props.placeholder.uri.empty()) {
    [self loadPlaceholder:props.placeholder.uri generation:generation];
    return;
  }
  // Copied into the block: props may change before the decode runs.
  const std::string blurhash = props.placeholder.blurhash;
  const std::string thumbhash = props.placeholder.thumbhash;

  __weak __typeof(self) weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    // A C++ exception leaving the block would crash; just show no placeholder.
    UIImage *placeholder = nil;
    try {
      const auto rgba = turboimage::decodePlaceholder(blurhash, thumbhash);
      placeholder = rgba ? imageFromRgba(*rgba) : nil;
    } catch (...) {
      NSLog(@"TurboImage: placeholder decode failed with a C++ exception");
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      __typeof(self) strongSelf = weakSelf;
      if (strongSelf == nil || placeholder == nil ||
          !strongSelf->_lifecycle.placeholderDecoded(generation, [strongSelf lifecycleProps])) {
        return;
      }
      strongSelf->_imageView.image = placeholder;
      [strongSelf placeImage];
    });
  });
}

// `placeholder.uri`: loaded like the source (view size; headers only on the
// source's origin) but unprocessed and silent; shown only if still current.
- (void)loadPlaceholder:(const std::string &)uri generation:(int64_t)generation {
  [self cancelPlaceholderLoad];
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (loader == nil || !_loadedRequest.has_value()) {
    return;
  }
  turboimage::ImageRequest request = *_loadedRequest;
  // The source's headers often carry credentials; another origin never gets them.
  if (!turboimage::sameOrigin(request.uri, uri)) {
    request.headers.clear();
  }
  request.uri = uri;
  request.cacheKey = std::nullopt;
  request.cachePolicy = turboimage::CachePolicy::Default;
  request.processing = {};
  request.allowDownscaling = true;
  TIRequestResult built = [self makeRequest:request];
  if (built.request == nil) {
    return;  // an unusable placeholder URI shows no placeholder
  }
  __weak __typeof(self) weakSelf = self;
  __block BOOL finished = NO;
  id<TIImageLoadTask> task = [loader loadImageWithRequest:built.request
      progress:nil
      completion:^(UIImage *image, id /* animation */, BOOL /* fromMemoryCache */, NSError *) {
        finished = YES;
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }
        strongSelf->_placeholderTask = nil;
        if (image != nil &&
            strongSelf->_lifecycle.placeholderDecoded(generation, [strongSelf lifecycleProps])) {
          // A still, even if animated.
          strongSelf->_imageView.image = image;
          [strongSelf placeImage];
        }
      }];
  // Keep the task only if it didn't complete synchronously.
  if (!finished) {
    _placeholderTask = task;
  }
}

- (void)cancelPlaceholderLoad {
  [_placeholderTask cancel];
  _placeholderTask = nil;
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  [self cancelPlaceholderLoad];
  // A fade still running would dissolve from this row's snapshot over the
  // next row's image.
  [_imageView.layer removeAllAnimations];
  // Stops everything and clears the image, without events.
  [self perform:_lifecycle.recycle() step:TIStepEffects{}];
  _upgradable = nil;
  _propsChanged = NO;
  _loadedRequest.reset();
  _needsPlaceholder = NO;
  _showPlaceholderOnFailureChanged = NO;
  _needsLiveTextUpdate = NO;
  [_liveText detach];
  _liveText = nil;
  _recyclingKeyChanged = NO;
  // Back to the default; the next updateProps diffs against defaults.
  _imageView.contentMode = toContentMode(defaultViewProps()->resizeMode);
  _imageView.frame = _container.bounds;
  // Leave `_props` alone: the base class diffs against it to reset
  // accessibilityLabel, testID, shadow, etc.
  _recycled = YES;
}

#pragma mark - Events

// nil before mount and after unmount; events are then dropped.
- (std::shared_ptr<const TurboImageViewEventEmitter>)emitter {
  return std::static_pointer_cast<const TurboImageViewEventEmitter>(_eventEmitter);
}

// `loadEventMask` bits: events JS has a handler for; others aren't sent.
// Read at emit time. `onProgress` uses `progressEnabled` instead.
typedef NS_OPTIONS(int, TILoadEvent) {
  TILoadEventStart = 1 << 0,
  TILoadEventSuccess = 1 << 1,
  TILoadEventFailure = 1 << 2,
  TILoadEventCompletion = 1 << 3,
};

- (BOOL)handles:(TILoadEvent)event {
  return (std::static_pointer_cast<const TurboImageViewProps>(_props)->loadEventMask & event) != 0;
}

- (void)emitStart {
  if (![self handles:TILoadEventStart]) {
    return;
  }
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
  if (![self handles:TILoadEventSuccess]) {
    return;
  }
  if (auto emitter = [self emitter]) {
    emitter->onSuccess({.width = size.width,
                        .height = size.height,
                        .source = std::string(source.UTF8String ?: "")});
  }
}

- (void)emitFailure:(turboimage::LoadErrorCode)code message:(NSString *)message {
  if (![self handles:TILoadEventFailure]) {
    return;
  }
  if (auto emitter = [self emitter]) {
    emitter->onFailure({
        .code = std::string(turboimage::loadErrorCodeName(code)),
        .error = std::string(message.UTF8String ?: ""),
    });
  }
}

- (void)emitCompletion:(NSString *)state {
  if (![self handles:TILoadEventCompletion]) {
    return;
  }
  if (auto emitter = [self emitter]) {
    emitter->onCompletion({.state = std::string(state.UTF8String)});
  }
}

@end
