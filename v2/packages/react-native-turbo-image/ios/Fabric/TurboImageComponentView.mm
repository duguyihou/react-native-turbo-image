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
#import "TILiveText.h"
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
  BOOL _needsLiveTextUpdate;
  // True once the loaded image is on screen; a late placeholder must not
  // replace it.
  BOOL _showingFinalImage;
  // The image of the previous request is still on screen while the current
  // load runs. It stands in for the placeholder, so no placeholder may
  // replace it. See startLoad.
  BOOL _showingPreviousImage;
  // `recyclingKey` changed in this transaction: the next load must not keep
  // the previous image.
  BOOL _recyclingKeyChanged;
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
  // leave a recycled view blank when it gets the same source as before
  // (smoke scenario `recycledSameSource`).
  const auto &oldViewProps =
      *std::static_pointer_cast<const TurboImageViewProps>(_recycled ? defaultViewProps() : _props);
  const auto &newViewProps = *std::static_pointer_cast<const TurboImageViewProps>(props);
  _recycled = NO;

  if (oldViewProps.source.uri != newViewProps.source.uri ||
      oldViewProps.source.cacheKey != newViewProps.source.cacheKey ||
      toHeaders(oldViewProps.source) != toHeaders(newViewProps.source) ||
      oldViewProps.cachePolicy != newViewProps.cachePolicy ||
      // Processors change the pixels, so they need a new load (served from
      // the disk original, or memory if this variant is cached).
      toProcessing(oldViewProps) != toProcessing(newViewProps) ||
      // Both decide how large the image is decoded (the core's decode-size
      // rule): `contain` needs fewer pixels than `cover`, `center` needs
      // them all. The image on screen may be too small for the new answer.
      oldViewProps.allowDownscaling != newViewProps.allowDownscaling ||
      oldViewProps.resizeMode != newViewProps.resizeMode) {
    _needsReload = YES;
  }
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
  if (_needsReload) {
    _needsReload = NO;
    // startLoad may clear the view, so the placeholder must be (re)applied.
    _needsPlaceholder = YES;
    [self startLoad];
  }
  // Consumed by the load above, or dropped: the key applies only to a load
  // in its own transaction.
  _recyclingKeyChanged = NO;
  if (_needsPlaceholder) {
    _needsPlaceholder = NO;
    [self applyPlaceholder];
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
  if (!_showingFinalImage || _imageView.image == nil) {
    return;  // the load's success calls this again
  }
  if (_liveText == nil) {
    _liveText = TIMakeLiveTextInteraction();
  }
  [_liveText analyzeImage:_imageView.image inImageView:_imageView];
}

// Decodes the placeholder off the main thread with the shared C++ core and
// shows it unless the real image (or a newer placeholder) got there first.
- (BOOL)placeholderAllowed {
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  return !_showingFinalImage && !_showingPreviousImage &&
         !(_loadFailed && !props.showPlaceholderOnFailure);
}

- (void)applyPlaceholder {
  const NSUInteger generation = ++_placeholderGeneration;
  if (![self placeholderAllowed]) {
    return;
  }
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  // memoryCacheKey: a synchronous memory-cache lookup (no decode, no disk).
  // The core says which keys the prop may name (an explicit cacheKey as
  // written, or a URI's canonical form); the first hit wins.
  if (!props.placeholder.memoryCacheKey.empty()) {
    id<TIImageLoading> loader = TIImageLoaderRegistry.sharedLoader;
    for (const auto &key : turboimage::memoryCacheKeyCandidates(props.placeholder.memoryCacheKey)) {
      UIImage *cached = [loader memoryCachedImageForKey:TIStringFromStd(key)];
      if (cached != nil) {
        _imageView.image = cached;
        break;
      }
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
  // What stays on screen while this load runs (expo-image's rule):
  //   * same `recyclingKey`: the previous image, so a changed source or
  //     processor swaps (and cross-fades) without a blank frame in between;
  //   * new `recyclingKey`: nothing, or the placeholder. The view is being
  //     reused for other content, and the old image would be wrong.
  // Only a loaded image is kept, never a placeholder or a failed view.
  _showingPreviousImage =
      (_showingFinalImage || _showingPreviousImage) && !_recyclingKeyChanged &&
      _imageView.image != nil;
  if (!_showingPreviousImage) {
    _imageView.image = nil;
  }
  _showingFinalImage = NO;
  _loadFailed = NO;
  // The old image's analysis must not outlive its request.
  [_liveText detach];
  _progressThrottle = turboimage::ProgressThrottle{};
  _lastProgressTotal = -1;

  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  // Same factory as the cache module, so prefetched keys always match.
  // Fabric applies props (and so starts loads) before mounting, when there
  // is no window to ask; RN's own screen scale is what `PixelRatio` reports
  // to JS, so `resize` means the same here as in the app's layout maths.
  const CGFloat pixelRatio = RCTScreenScale();
  // The view's size bounds the decode (`allowDownscaling`). Fabric applies
  // layout metrics before finalizeUpdates, on mount as on update, so the
  // bounds are this transaction's. The size is taken once, here: a view that
  // grows later keeps the image it has.
  // TODO: reload when the view outgrows the decoded image (expo-image does
  // not either; `allowDownscaling={false}` is the documented way out).
  const CGSize viewPixelSize = CGSizeMake(self.bounds.size.width * pixelRatio,
                                          self.bounds.size.height * pixelRatio);
  const auto built = TIMakeImageRequest(
      {
          .uri = props.source.uri,
          .cacheKey = TIOptionalCacheKey(props.source.cacheKey),
          .cachePolicy = toCorePolicy(props.cachePolicy),
          .processing = toProcessing(props),
          .pixelRatio = pixelRatio,
          .headers = toHeaders(props.source),
          .allowDownscaling = props.allowDownscaling,
          .resizeMode = toCoreResizeMode(props.resizeMode),
      },
      viewPixelSize);
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
          strongSelf->_showingPreviousImage = NO;
          // A successful load ends progress at 100% (core rule, see finish()).
          const int64_t total = strongSelf->_lastProgressTotal;
          if (strongSelf->_progressThrottle.finish(total)) {
            [strongSelf emitProgress:total total:total];
          }
          [strongSelf showFinalImage:image animated:!fromMemoryCache];
          [strongSelf updateLiveText];
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

// 1.x semantics: without `showPlaceholderOnFailure` the placeholder is
// removed when the load fails. Also stops a placeholder decode still in
// flight from appearing after the failure.
- (void)applyFailureToPlaceholder {
  _loadFailed = YES;
  // A previous image kept during the load goes either way: it is not what
  // `source` names, and leaving it up would hide the failure.
  const BOOL hadPreviousImage = _showingPreviousImage;
  _showingPreviousImage = NO;
  const auto &props = *std::static_pointer_cast<const TurboImageViewProps>(_props);
  if (!props.showPlaceholderOnFailure) {
    ++_placeholderGeneration;
    _imageView.image = nil;
  } else if (hadPreviousImage) {
    // The placeholder was held back while the previous image stood in.
    _imageView.image = nil;
    [self applyPlaceholder];
  }
}

- (void)prepareForRecycle {
  [super prepareForRecycle];
  [_task cancel];
  _task = nil;
  _imageView.image = nil;
  _needsReload = NO;
  _needsPlaceholder = NO;
  _needsLiveTextUpdate = NO;
  [_liveText detach];
  _liveText = nil;
  _showingFinalImage = NO;
  _showingPreviousImage = NO;
  _recyclingKeyChanged = NO;
  _loadFailed = NO;
  ++_placeholderGeneration;  // drop any decode still in flight
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
