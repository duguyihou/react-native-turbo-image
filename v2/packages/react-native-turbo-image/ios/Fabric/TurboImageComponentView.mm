// Fabric host view for <TurboImage> on iOS.
//
// Responsibilities, in order:
//   1. Receive codegen props from React.
//   2. Ask the shared C++ core to resolve them into a `ResolvedRequest`
//      (same code Android runs, RFC rule 4).
//   3. Hand the resolved request to whichever `TIImageLoading` adapter is
//      registered (Nuke by default) and display the result.
//
// When each of those happens, what stays on screen meanwhile and which load
// events JS sees is not decided here: the core's `ViewLifecycle` decides, and
// this view carries out the effects it returns (`perform:step:`).
//
// This file is the *only* place where React Native, the C++ core and the
// loader seam meet. It must not import Nuke.

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

// The seam's error codes are the core's, repeated in plain ObjC because the
// seam header cannot include C++. `loadDidFinishWithImage:` casts one to the
// other, so a value added or renumbered on one side only must not compile.
#define TI_ASSERT_SAME_CODE(seam, core)                                              \
  static_assert(static_cast<int>(seam) == static_cast<int>(turboimage::LoadErrorCode::core), \
                "TIImageLoadErrorCode and turboimage::LoadErrorCode disagree")
TI_ASSERT_SAME_CODE(TIImageLoadErrorUnknown, Unknown);
TI_ASSERT_SAME_CODE(TIImageLoadErrorInvalidRequest, InvalidRequest);
TI_ASSERT_SAME_CODE(TIImageLoadErrorNotCached, NotCached);
TI_ASSERT_SAME_CODE(TIImageLoadErrorNetwork, Network);
TI_ASSERT_SAME_CODE(TIImageLoadErrorDecode, Decode);
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
      // No UIKit mode: placeImage computes it. Fit until there is an image.
      return UIViewContentModeScaleAspectFit;
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

// Codegen's header structs have no operator==; this is the comparison and
// the conversion in one place.
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

// Loud where a developer will see it (a redbox in development), harmless
// where a user would: the effect is skipped, which at worst leaves one image
// unloaded.
void TIUnexpectedEffect(NSString *kind) {
  RCTLogError(@"TurboImage: the lifecycle sent %@ from a step that cannot produce it", kind);
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

// The effects of the lifecycle that only one kind of step can produce, and
// that need what that step knows: the request a reload resolved, or what the
// adapter called back with. Each caller of perform:step: sets the ones its
// step can produce, as blocks closing over that knowledge, so no effect has
// to dig its context out of a loosely typed argument.
//
// The lifecycle never sends an effect from a step that cannot produce it
// (`StartLoad` from a callback, say). If it ever did, the block is nil: that
// is a bug in the core or here, and it is reported, not acted on.
struct TIStepEffects {
  void (^deliverInvalidRequest)(void) = nil;
  void (^startLoad)(int64_t token) = nil;
  void (^deliverSuccess)(void) = nil;
  void (^deliverFailure)(void) = nil;
};

// The view's content view: it clips to the content box (inside the border
// and padding) and holds the image view, which `placeImage` may make larger
// than the box (cover) or smaller (contain) and move off centre
// (`contentPosition`). UIKit's content modes cannot combine a scale with an
// edge, so the image view's frame does it. Its layoutSubviews asks the view
// to place the image again whenever the box changes.
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
  // Every decision about what the view shows and which load events JS sees
  // is the core's (the same code the Android view runs). This view says what
  // happened and carries out the effects it gets back; see perform:step:.
  turboimage::ViewLifecycle _lifecycle;
  // Cancels the load in flight; nil when there is none.
  id<TIImageLoadTask> _task;
  // Set by updateProps, consumed by finalizeUpdates.
  BOOL _propsChanged;
  // The request the current load was started for; empty before a view's
  // first load, and again after a recycle.
  std::optional<turboimage::ImageRequest> _loadedRequest;
  BOOL _needsPlaceholder;
  BOOL _needsLiveTextUpdate;
  // `recyclingKey` changed in this transaction: the next load must not keep
  // the previous image.
  BOOL _recyclingKeyChanged;
  // Per-load progress throttle (core rule shared with Android).
  turboimage::ProgressThrottle _progressThrottle;
  // Last Content-Length seen this load, for the throttle's finish() step.
  int64_t _lastProgressTotal;
  // Created on first use; nil while Live Text is off or unsupported.
  id<TILiveTextInteraction> _liveText;
  // Set by prepareForRecycle, consumed by the next updateProps: this view's
  // own state was reset to the spec defaults, so that is what the incoming
  // props must be compared with. See updateProps.
  BOOL _recycled;
  // The request of the image on screen, when it was decoded for this view's
  // size and could be loaded again larger if the view grows
  // (`turboimage::needsLargerDecode`); nil otherwise. With the image's size
  // in pixels, and the view's when the image was loaded (the request's
  // `decodeSize`, or the size an upgrade failed at, see upgradeIfOutgrown).
  TIImageRequest *_upgradable;
  turboimage::PixelSize _upgradableDecoded;
  turboimage::PixelSize _upgradableLoadedFor;
  // The placeholder's own load, for a placeholder given as an image
  // (`placeholder.uri`). Never reported to JS; cancelled when a newer
  // placeholder, the image itself or a recycle makes it moot.
  id<TIImageLoadTask> _placeholderTask;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<TurboImageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _props = defaultViewProps();

    // The loader's image view, because playing an animation takes one of its
    // own (TIImageLoading.h). A plain one if no adapter is linked: such a
    // view only ever reports that, and shows placeholders.
    _imageView = [TIImageLoaderRegistry.sharedLoader makeImageView] ?: [UIImageView new];
    _imageView.clipsToBounds = YES;
    // The spec default (`contain`, 1.x's default), read from the default
    // props so the two cannot drift apart.
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
  }
  return self;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps {
  // Fabric keeps `_props` across a recycle and remounts the view with
  // `oldProps:nullptr`, so `_props` is still the previous life's props here.
  // The base class needs exactly that: it diffs against `_props` to undo
  // what the previous life set on the UIView (accessibility, opacity, ...).
  // This view's own state was instead reset by prepareForRecycle, so its
  // props are compared with the defaults. Comparing them with `_props` would
  // leave a recycled view without the placeholder or Live Text of its new
  // life when they equal the previous life's. (The request needs no such
  // care: prepareForRecycle forgets `_loadedRequest`, so the first props of
  // a new life always load. Smoke scenario `recycledSameSource`.)
  const auto &oldViewProps =
      *std::static_pointer_cast<const TurboImageViewProps>(_recycled ? defaultViewProps() : _props);
  const auto &newViewProps = *std::static_pointer_cast<const TurboImageViewProps>(props);
  _recycled = NO;

  // Whether the request props changed is not worked out here: finalizeUpdates
  // compares the whole request with the one the current load was started
  // for, once `_props` holds the new values.
  _propsChanged = YES;
  // Not a request prop: a new key alone starts no load, because the image
  // on screen is still the one `source` names. It only decides how the load
  // started in this same transaction treats the previous image.
  if (oldViewProps.recyclingKey != newViewProps.recyclingKey) {
    _recyclingKeyChanged = YES;
  }
  // Any placeholder field: a change to it alone starts no reload.
  if (oldViewProps.placeholder.blurhash != newViewProps.placeholder.blurhash ||
      oldViewProps.placeholder.thumbhash != newViewProps.placeholder.thumbhash ||
      oldViewProps.placeholder.memoryCacheKey != newViewProps.placeholder.memoryCacheKey ||
      oldViewProps.placeholder.uri != newViewProps.placeholder.uri) {
    _needsPlaceholder = YES;
  }
  if (oldViewProps.enableLiveTextInteraction != newViewProps.enableLiveTextInteraction) {
    // Applied in finalizeUpdates, once `_props` holds the new value.
    _needsLiveTextUpdate = YES;
  }
  // resizeMode and contentPosition are applied in finalizeUpdates, by
  // placeImage, once `_props` holds them.

  [super updateProps:props oldProps:oldProps];
}

// Loading is deferred to finalizeUpdates so a single transaction that
// changes several request props starts exactly one load.
- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask {
  [super finalizeUpdates:updateMask];
  [self placeImage];
  if (_propsChanged) {
    _propsChanged = NO;
    // A new load whenever the request differs from the one on screen, and for
    // a view's first props whatever they say: a view mounted without a source
    // reports that (`invalidRequest`) instead of staying silent. Comparing
    // the core's request, not a list of props kept here, means a field added
    // to it can never be forgotten on one platform.
    auto request = [self coreRequest];
    if (!_loadedRequest.has_value() || *_loadedRequest != request) {
      _loadedRequest = std::move(request);
      // A reload may clear the view, so the placeholder must be (re)applied.
      _needsPlaceholder = YES;
      [self reload];
    }
  }
  // Consumed by the load above, or dropped: the key applies only to a load
  // in its own transaction.
  _recyclingKeyChanged = NO;
  if (_needsPlaceholder) {
    _needsPlaceholder = NO;
    [self perform:_lifecycle.applyPlaceholder([self lifecycleProps]) step:TIStepEffects{}];
  }
  if (_needsLiveTextUpdate) {
    _needsLiveTextUpdate = NO;
    [self updateLiveText];
  }
}

#pragma mark - Live Text

// Analyses the loaded image only: never a placeholder, and nothing while a
// load is in flight. Turning the prop off removes the interaction at once.
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

// The props the core's lifecycle depends on, as they are now.
- (turboimage::LifecycleProps)lifecycleProps {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  // JS allows one placeholder kind at a time; `memoryCacheKey` wins if an
  // app passes several anyway, as it always has.
  const auto kind = !props.placeholder.memoryCacheKey.empty()
                        ? turboimage::PlaceholderKind::MemoryCacheKey
                        // An image placeholder arrives later, like a decoded
                        // hash, and the lifecycle treats it the same way.
                        : !props.placeholder.blurhash.empty() || !props.placeholder.thumbhash.empty() ||
                                  !props.placeholder.uri.empty()
                              ? turboimage::PlaceholderKind::Hash
                              : turboimage::PlaceholderKind::None;
  return {.placeholder = kind, .showPlaceholderOnFailure = props.showPlaceholderOnFailure};
}

// A request prop changed: resolve the new request and let the lifecycle end
// the old load, decide what stays on screen, and start the new one.
- (void)reload {
  // The image on screen is about to be replaced; there is nothing to upgrade
  // until the new one arrives. (A running upgrade is cancelled by the
  // lifecycle, below.)
  _upgradable = nil;
  // The old image's analysis must not outlive its request.
  [_liveText detach];
  _progressThrottle = turboimage::ProgressThrottle{};
  _lastProgressTotal = -1;

  // Requests that cannot be started fail before onStart: no load ever began.
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

// Carries out the lifecycle's effects, in order. The lifecycle decided;
// nothing here chooses whether an effect applies.
//
// The blocks in `step` capture `self` strongly. They run before this
// returns and the struct lives on the caller's stack, so that is no cycle.
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

  [self emitStart];

  // The adapter drops callbacks after cancel, but the lifecycle guards by
  // token as well: a callback from a load that was replaced gets no effects
  // back, so it cannot touch this view. The blocks only pass on what
  // happened; what it means for the view is the lifecycle's to say.
  __weak __typeof(self) weakSelf = self;
  // No `onProgress` handler in JS: no block, so the loader tracks no
  // progress (Nuke: no progress task per load) and no events are sent.
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
        // `image` is nil when the load failed; `error` then says why.
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
          [strongSelf perform:strongSelf->_lifecycle.loadFailed(token, [strongSelf lifecycleProps])
                         step:step];
        }
      }];
  // Already finished if the completion ran inside the call above: there is
  // nothing left to cancel, so the task is not kept.
  if (_lifecycle.isInFlight(token)) {
    _task = task;
  }
}

// Turns the request and the view's size into a seam request, through
// the same factory as the cache module, so prefetched keys always match.
- (TIRequestResult)makeRequest:(const turboimage::ImageRequest &)request {
  const CGFloat pixelRatio = request.pixelRatio;
  // The view's size bounds the decode (`allowDownscaling`). Fabric applies
  // layout metrics before finalizeUpdates, on mount as on update, so the
  // bounds are this transaction's. A view that grows later loads the image
  // again at its new size (upgradeIfOutgrown), through this same method.
  const CGSize viewPixelSize = CGSizeMake(self.bounds.size.width * pixelRatio,
                                          self.bounds.size.height * pixelRatio);
  return TIMakeImageRequest(request, viewPixelSize);
}

// The view's size in pixels.
- (turboimage::PixelSize)viewPixelSize {
  const CGFloat pixelRatio = RCTScreenScale();
  return {self.bounds.size.width * pixelRatio, self.bounds.size.height * pixelRatio};
}

// The current props as the core's request: everything they say about which
// image to load and how.
- (turboimage::ImageRequest)coreRequest {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  return {
      .uri = props.source.uri,
      .cacheKey = TIOptionalCacheKey(props.source.cacheKey),
      .cachePolicy = toCorePolicy(props.cachePolicy),
      // Processors change the pixels, so they need a new load (served from
      // the disk original, or memory if this variant is cached).
      .processing = toProcessing(props),
      // Fabric applies props (and so starts loads) before mounting, when
      // there is no window to ask; RN's own screen scale is what `PixelRatio`
      // reports to JS, so `resize` means the same here as in the app's
      // layout maths.
      .pixelRatio = RCTScreenScale(),
      .headers = toHeaders(props.source),
      // Both decide how large the image is decoded (the core's decode-size
      // rule): `contain` needs fewer pixels than `cover`, `center` needs
      // them all. The image on screen may be too small for the new answer.
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
  // A successful load ends progress at 100% (core rule, see finish()).
  if (_progressThrottle.finish(_lastProgressTotal)) {
    [self emitProgress:_lastProgressTotal total:_lastProgressTotal];
  }
  [self showFinalImage:image animation:animation fade:!fromMemoryCache];
  [self updateLiveText];
  // In pixels, as on Android. `size` alone is in points, which differs for
  // any image whose scale is not 1: a processed SVG drawn at its own size
  // carries the screen's scale so that it keeps its size in points.
  const CGFloat scale = image.scale > 0 ? image.scale : 1;
  [self emitSuccess:CGSizeMake(image.size.width * scale, image.size.height * scale)
             source:source];
}

#pragma mark - Upgrades

// A view outgrows its image when it is resized after the load: a zoom, a
// rotation, a card that expands. Fabric applies the new frame here.
- (void)updateLayoutMetrics:(const LayoutMetrics &)layoutMetrics
           oldLayoutMetrics:(const LayoutMetrics &)oldLayoutMetrics {
  [super updateLayoutMetrics:layoutMetrics oldLayoutMetrics:oldLayoutMetrics];
  const auto &size = layoutMetrics.frame.size;
  const auto &oldSize = oldLayoutMetrics.frame.size;
  if (size.width > oldSize.width || size.height > oldSize.height) {
    [self upgradeIfOutgrown];
  }
}

// Notes an image that was sized for this view, then sees whether the view
// already outgrew it.
//
// Not for an animated image: Nuke's player decodes its frames for the view's
// size itself, and replacing the image would restart it. Not for a vector
// (SVG): it has no pixels (`CGImage` is nil) and is drawn sharp at any size.
// Not for a request whose decode does not follow the view: `decodeSize`
// with no height is a `resize` width, and zero is the original size.
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

// Loads the image again at the view's size if the view has grown past it
// (`turboimage::needsLargerDecode`). Silent: no events, no progress, and on
// failure the image already shown stays (`ViewLifecycle::startUpgrade`).
- (void)upgradeIfOutgrown {
  if (_upgradable == nil || !_loadedRequest.has_value()) {
    return;
  }
  const turboimage::PixelSize now = [self viewPixelSize];
  if (!turboimage::needsLargerDecode(_upgradableDecoded, _upgradableLoadedFor, now,
                                     _upgradable.decodeFill)) {
    return;
  }
  // The request at the view's current size, through the same factory.
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
          // Not again for this image: recorded as loaded for the size it
          // failed at, the rule takes the image for the source at its own
          // size. A new source, or a reload, starts over.
          strongSelf->_upgradableLoadedFor = now;
          return;
        }
        if (!strongSelf->_lifecycle.upgradeSucceeded(token)) {
          return;  // superseded by a reload, recycle or drop
        }
        strongSelf->_task = nil;
        // No fade: the same picture, only sharper, replaces itself.
        [loader displayImage:image animation:animation inImageView:strongSelf->_imageView];
        [strongSelf placeImage];
        [strongSelf updateLiveText];
        // Records the new image and asks again, in case the view kept
        // growing meanwhile.
        [strongSelf rememberImage:image animation:animation request:request];
      }];
  // Already finished if the completion ran inside the call above.
  if (_lifecycle.isUpgrading(token)) {
    _task = task;
  }
}

- (void)deliverFailure:(NSError *)error {
  // The seam guarantees TIImageLoadErrorDomain; anything else is an adapter
  // bug, reported as unknown.
  const auto code = [error.domain isEqualToString:TIImageLoadErrorDomain]
                        ? static_cast<turboimage::LoadErrorCode>(error.code)
                        : turboimage::LoadErrorCode::Unknown;
  [self emitFailure:code message:error.localizedDescription ?: @"Unknown error"];
}

// Cross-fades from whatever is shown (placeholder, previous image or
// blank). Memory-cache hits appear instantly, the same rule as Coil's crossfade on Android, so
// scrolling back through a list does not re-fade every cell.
//
// The loader puts it on screen, because an animated image is played by the
// loader (`animation`); placeholders and clearing are plain `image` sets.
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
                    // Inside the transition, so its end state has the new frame.
                    [self placeImage];
                  }
                  completion:nil];
}

#pragma mark - Placeholder

// memoryCacheKey: a synchronous memory-cache lookup (no decode, no disk).
// The core says which keys the prop may name (an explicit cacheKey as
// written, or a URI's canonical form); the first hit wins, and a miss clears
// the view.
// Places the image view in the content box for resizeMode and
// contentPosition. Cover and contain centred: UIKit's content mode, with the
// image view filling the box, as before contentPosition existed. Otherwise
// the core's placeImage gives the rectangle, the same one Android draws
// into. Called whenever the image, the props or the box change, since the
// rectangle depends on all three.
//
// Center and scale-down always go through placeImage, because they draw the
// image at its own size and UIKit takes that from `UIImage.size`, in points
// at the image's scale. The adapter decodes at scale 1, so a 600 px image
// was 600 points wide under UIKit's center mode, three times its size on
// Android, where a bitmap's own size is its pixels at the screen's density.
// Both now use pixels over the screen scale; a vector (no CGImage) keeps
// its canvas, which is already in points.
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

// Decodes the placeholder off the main thread with the shared C++ core and
// shows it unless the real image (or a newer placeholder) got there first,
// which the lifecycle answers by the decode's generation.
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
    // A C++ exception that leaves this block terminates the app, and the
    // decode allocates. A placeholder is optional: without memory for it,
    // the view simply shows none.
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

// An image placeholder: loaded like a source (from the caches when it is
// there), at the view's size, with the source's headers, unprocessed and
// without events, then shown unless the image or a newer placeholder got
// there first, which the lifecycle answers by generation as for a decode.
- (void)loadPlaceholder:(const std::string &)uri generation:(int64_t)generation {
  [self cancelPlaceholderLoad];
  id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
  if (loader == nil || !_loadedRequest.has_value()) {
    return;
  }
  turboimage::ImageRequest request = *_loadedRequest;
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
          // A still, even of an animated image: it is only a stand-in.
          strongSelf->_imageView.image = image;
          [strongSelf placeImage];
        }
      }];
  // Already finished if the completion ran inside the call (a memory hit):
  // nothing is left to cancel.
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
  // Stops the load and any decode and clears the image, with no event: the
  // component that was listening is gone.
  [self perform:_lifecycle.recycle() step:TIStepEffects{}];
  _upgradable = nil;
  _propsChanged = NO;
  _loadedRequest.reset();
  _needsPlaceholder = NO;
  _needsLiveTextUpdate = NO;
  [_liveText detach];
  _liveText = nil;
  _recyclingKeyChanged = NO;
  // Back to the spec default, like the image above: the next updateProps
  // compares this view's props with the defaults (see `_recycled`).
  _imageView.contentMode = toContentMode(defaultViewProps()->resizeMode);
  _imageView.frame = _container.bounds;
  // `_props` is deliberately left alone. It belongs to the base class, which
  // diffs the next life's props against it; replacing it with the defaults
  // made a recycled view keep the previous life's accessibilityLabel,
  // testID and shadow whenever the new life left them unset. (Not opacity:
  // the base class re-applies that one on every update.) Checked once with
  // a temporary log of `accessibilityLabel` and `layer.shadowOpacity` across
  // a recycle; no smoke scenario can see either from JS.
  _recycled = YES;
}

#pragma mark - Events

// One accessor so every emitter shares the "no emitter yet" check (events
// fired before mount, or after unmount, are dropped).
- (std::shared_ptr<const TurboImageViewEventEmitter>)emitter {
  return std::static_pointer_cast<const TurboImageViewEventEmitter>(_eventEmitter);
}

// `loadEventMask`'s bits (TurboImageViewNativeComponent.ts): the events JS
// has a handler for. The others are not built or sent; JS would drop them.
// Read now, not when the load started, as JS looks for its handler on
// arrival. `onProgress` is gated by `progressEnabled` instead.
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
