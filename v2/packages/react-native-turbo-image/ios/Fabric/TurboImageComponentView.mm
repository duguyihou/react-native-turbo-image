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

@interface TurboImageComponentView () <RCTTurboImageViewViewProtocol>
@end

@implementation TurboImageComponentView {
  UIImageView *_imageView;
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
}

+ (ComponentDescriptorProvider)componentDescriptorProvider {
  return concreteComponentDescriptorProvider<TurboImageViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _props = defaultViewProps();

    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.clipsToBounds = YES;
    // The spec default (`contain`, 1.x's default), read from the default
    // props so the two cannot drift apart.
    _imageView.contentMode = toContentMode(defaultViewProps()->resizeMode);
    self.contentView = _imageView;
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
  if (oldViewProps.placeholder.blurhash != newViewProps.placeholder.blurhash ||
      oldViewProps.placeholder.thumbhash != newViewProps.placeholder.thumbhash ||
      oldViewProps.placeholder.memoryCacheKey != newViewProps.placeholder.memoryCacheKey) {
    _needsPlaceholder = YES;
  }
  if (oldViewProps.enableLiveTextInteraction != newViewProps.enableLiveTextInteraction) {
    // Applied in finalizeUpdates, once `_props` holds the new value.
    _needsLiveTextUpdate = YES;
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
                        : !props.placeholder.blurhash.empty() || !props.placeholder.thumbhash.empty()
                              ? turboimage::PlaceholderKind::Hash
                              : turboimage::PlaceholderKind::None;
  return {.placeholder = kind, .showPlaceholderOnFailure = props.showPlaceholderOnFailure};
}

// A request prop changed: resolve the new request and let the lifecycle end
// the old load, decide what stays on screen, and start the new one.
- (void)reload {
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
  id<TIImageLoadTask> task = [TIImageLoaderRegistry.sharedLoader loadImageWithRequest:request
      progress:^(int64_t completed, int64_t total) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_lifecycle.isInFlight(token)) {
          [strongSelf loadDidProgress:completed total:total];
        }
      }
      completion:^(UIImage *image, BOOL fromMemoryCache, NSError *error) {
        __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
          return;
        }
        // `image` is nil when the load failed; `error` then says why.
        TIStepEffects step;
        if (image != nil) {
          step.deliverSuccess = ^{
            [strongSelf deliverSuccess:image fromMemoryCache:fromMemoryCache source:source];
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
  // bounds are this transaction's. The size is taken once, here: a view that
  // grows later keeps the image it has.
  // TODO: reload when the view outgrows the decoded image (expo-image does
  // not either; `allowDownscaling={false}` is the documented way out).
  const CGSize viewPixelSize = CGSizeMake(self.bounds.size.width * pixelRatio,
                                          self.bounds.size.height * pixelRatio);
  return TIMakeImageRequest(request, viewPixelSize);
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
       fromMemoryCache:(BOOL)fromMemoryCache
                source:(NSString *)source {
  // A successful load ends progress at 100% (core rule, see finish()).
  if (_progressThrottle.finish(_lastProgressTotal)) {
    [self emitProgress:_lastProgressTotal total:_lastProgressTotal];
  }
  [self showFinalImage:image animated:!fromMemoryCache];
  [self updateLiveText];
  // In pixels, as on Android. `size` alone is in points, which differs for
  // any image whose scale is not 1: a processed SVG drawn at its own size
  // carries the screen's scale so that it keeps its size in points.
  const CGFloat scale = image.scale > 0 ? image.scale : 1;
  [self emitSuccess:CGSizeMake(image.size.width * scale, image.size.height * scale)
             source:source];
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

#pragma mark - Placeholder

// memoryCacheKey: a synchronous memory-cache lookup (no decode, no disk).
// The core says which keys the prop may name (an explicit cacheKey as
// written, or a URI's canonical form); the first hit wins, and a miss clears
// the view.
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
}

// Decodes the placeholder off the main thread with the shared C++ core and
// shows it unless the real image (or a newer placeholder) got there first,
// which the lifecycle answers by the decode's generation.
- (void)decodePlaceholder:(int64_t)generation {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
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
    });
  });
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  // Stops the load and any decode and clears the image, with no event: the
  // component that was listening is gone.
  [self perform:_lifecycle.recycle() step:TIStepEffects{}];
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
