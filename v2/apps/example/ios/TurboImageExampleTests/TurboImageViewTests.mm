// `TurboImageComponentView` itself, between its props and the loader seam:
// when it loads, and what it asks the loader for. The iOS counterpart of
// TurboImageViewTest.kt.
//
// The adapter tests (packages/react-native-turbo-image/ios/Tests) drive the
// real Nuke adapter; these register `TIFakeLoader` instead, so a test
// decides when each load succeeds or fails and sees every load the view
// starts. The core is the real one, so the decisions under test are the ones
// the app makes.
//
// The view is driven the way Fabric mounts it: `updateProps:`, then
// `updateLayoutMetrics:` (the frame), then `finalizeUpdates:`, where loads
// start. Through React Native's public `RCTComponentViewProtocol`, so the
// view's own header (private under CocoaPods) is not needed. It has no event
// emitter here, so events are dropped; which events a load sends is the
// core's decision and is covered by the Android view test and the smoke
// suite.
//
// Covered: upgrades (a view that outgrows its image loads it again at its
// new size). TODO: placeholders, `recyclingKey` and Live Text.

#import <XCTest/XCTest.h>

#import <React/RCTComponentViewProtocol.h>
#import <React/RCTUtils.h>
#import <TurboImage/TIImageLoading.h>
#import <react/renderer/components/TurboImageSpec/Props.h>

using namespace facebook::react;

#pragma mark - Fake loader

/// One load the view started. Finishes when the test says so.
@interface TIFakeLoad : NSObject <TIImageLoadTask>
@property(nonatomic, readonly) TIImageRequest *request;
@property(nonatomic, readonly) BOOL cancelled;
@end

@implementation TIFakeLoad {
  TIImageLoadCompletion _completion;
}

- (instancetype)initWithRequest:(TIImageRequest *)request completion:(TIImageLoadCompletion)completion {
  if ((self = [super init])) {
    _request = request;
    _completion = [completion copy];
  }
  return self;
}

- (void)cancel {
  _cancelled = YES;
}

/// Delivers a still of `pixels` (scale 1, so points are pixels).
- (void)succeedWithPixels:(CGSize)pixels {
  [self succeedWithPixels:pixels animation:nil];
}

- (void)succeedWithPixels:(CGSize)pixels animation:(nullable id)animation {
  NSAssert(!_cancelled, @"a cancelled load cannot succeed");
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
  format.scale = 1;
  UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:pixels format:format]
      imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemTealColor setFill];
        [context fillRect:CGRectMake(0, 0, pixels.width, pixels.height)];
      }];
  _completion(image, animation, NO, nil);
}

- (void)fail {
  NSAssert(!_cancelled, @"a cancelled load cannot fail");
  _completion(nil, nil, NO,
              [NSError errorWithDomain:TIImageLoadErrorDomain code:TIImageLoadErrorNetwork userInfo:nil]);
}

@end

/// A loader whose loads finish when a test says so. Never calls back after a
/// cancel (the seam's contract).
@interface TIFakeLoader : NSObject <TIImageLoading>
@property(nonatomic, readonly) NSMutableArray<TIFakeLoad *> *loads;
@end

@implementation TIFakeLoader

- (instancetype)init {
  if ((self = [super init])) {
    _loads = [NSMutableArray new];
  }
  return self;
}

- (id<TIImageLoadTask>)loadImageWithRequest:(TIImageRequest *)request
                                   progress:(TIImageLoadProgress)progress
                                 completion:(TIImageLoadCompletion)completion {
  TIFakeLoad *load = [[TIFakeLoad alloc] initWithRequest:request completion:completion];
  [_loads addObject:load];
  return load;
}

- (UIImageView *)makeImageView {
  return [UIImageView new];
}

- (void)displayImage:(UIImage *)image animation:(id)animation inImageView:(UIImageView *)imageView {
  imageView.image = image;
}

// The view tests never reach the cache module's half of the seam.
- (id<TIImageLoadTask>)prefetchRequest:(TIImageRequest *)request completion:(void (^)(BOOL))completion {
  [NSException raise:NSInternalInconsistencyException format:@"not used"];
  return nil;
}
- (void)removeCachedImageForRequest:(TIImageRequest *)request {}
- (void)clearMemoryCache {}
- (void)clearDiskCache {}
- (UIImage *)memoryCachedImageForKey:(NSString *)cacheKey {
  return nil;
}

@end

#pragma mark - Tests

static NSString *const kURL = @"https://images.example.com/photos/harbour.jpg";

@interface TurboImageViewTests : XCTestCase
@end

@implementation TurboImageViewTests {
  id<TIImageLoading> _previousLoader;
  TIFakeLoader *_loader;
  UIView<RCTComponentViewProtocol> *_view;
  std::shared_ptr<const TurboImageViewProps> _props;
  LayoutMetrics _layout;
  CGFloat _scale;
}

- (void)setUp {
  // The host app registered the Nuke adapter; the view reads the registry
  // when it is created and on every load.
  _previousLoader = TIImageLoaderRegistry.sharedLoader;
  _loader = [TIFakeLoader new];
  TIImageLoaderRegistry.sharedLoader = _loader;
  _view = [[NSClassFromString(@"TurboImageComponentView") alloc] initWithFrame:CGRectZero];
  XCTAssertNotNil(_view);
  _layout = EmptyLayoutMetrics;
  _scale = RCTScreenScale();
}

- (void)tearDown {
  TIImageLoaderRegistry.sharedLoader = _previousLoader;
}

#pragma mark Upgrades

- (void)testAViewThatGrowsPastHalfAgainLoadsItsImageAgain {
  [self showLoadedImage];
  UIImage *shown = [self imageOnScreen];

  [self resize:CGSizeMake(200, 200)];

  XCTAssertEqual(_loader.loads.count, 2u, @"an upgrade starts");
  TIFakeLoad *upgrade = _loader.loads[1];
  XCTAssertEqualObjects(upgrade.request.url, _loader.loads[0].request.url);
  XCTAssertTrue(CGSizeEqualToSize(upgrade.request.decodeSize, [self pixels:CGSizeMake(200, 200)]),
                @"at the view's new size");
  XCTAssertEqual([self imageOnScreen], shown, @"the image stays while it loads");

  [upgrade succeedWithPixels:[self pixels:CGSizeMake(200, 200)]];

  XCTAssertNotEqual([self imageOnScreen], shown);
}

- (void)testGrowingByHalfOrLessKeepsTheImage {
  [self showLoadedImage];

  [self resize:CGSizeMake(150, 150)];  // exactly 1.5x

  XCTAssertEqual(_loader.loads.count, 1u);
}

- (void)testAnImageSmallerThanItsViewIsNeverLoadedAgain {
  // The decode never upscales, so an image that came out smaller than its
  // view is the source at its own size.
  [self showLoadedImageOfPixels:CGSizeMake(20, 10)];

  [self resize:CGSizeMake(300, 300)];

  XCTAssertEqual(_loader.loads.count, 1u);
}

- (void)testAnImageNotDecodedForTheViewIsNeverLoadedAgain {
  // With downscaling off the image is decoded at its own size.
  [self setProps:^(TurboImageViewProps &props) {
    props.allowDownscaling = false;
  }];
  [self showLoadedImage];

  [self resize:CGSizeMake(300, 300)];

  XCTAssertEqual(_loader.loads.count, 1u);
}

- (void)testAnAnimatedImageIsNeverLoadedAgain {
  // Nuke's player decodes each frame for the view's size itself, and a new
  // image would restart the animation.
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [_loader.loads[0] succeedWithPixels:[self pixels:CGSizeMake(100, 100)] animation:[NSObject new]];

  [self resize:CGSizeMake(300, 300)];

  XCTAssertEqual(_loader.loads.count, 1u);
}

- (void)testAViewThatGrewDuringItsLoadUpgradesWhenTheLoadSucceeds {
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];

  [self resize:CGSizeMake(200, 200)];
  XCTAssertEqual(_loader.loads.count, 1u, @"no upgrade beside a load");

  [_loader.loads[0] succeedWithPixels:[self pixels:CGSizeMake(100, 100)]];

  XCTAssertEqual(_loader.loads.count, 2u);
}

- (void)testAnUpgradedImageCanBeUpgradedAgain {
  [self showLoadedImage];
  [self resize:CGSizeMake(200, 200)];
  [_loader.loads[1] succeedWithPixels:[self pixels:CGSizeMake(200, 200)]];

  [self resize:CGSizeMake(400, 400)];

  XCTAssertEqual(_loader.loads.count, 3u);
}

- (void)testAFailedUpgradeKeepsTheImageAndIsNotRetried {
  [self showLoadedImage];
  UIImage *shown = [self imageOnScreen];
  [self resize:CGSizeMake(200, 200)];

  [_loader.loads[1] fail];
  [self resize:CGSizeMake(400, 400)];

  XCTAssertEqual([self imageOnScreen], shown);
  XCTAssertEqual(_loader.loads.count, 2u, @"no second attempt for this image");
}

- (void)testANewSourceCancelsAnUpgrade {
  [self showLoadedImage];
  [self resize:CGSizeMake(200, 200)];
  TIFakeLoad *upgrade = _loader.loads[1];

  [self setSource:[kURL stringByAppendingString:@"?other"]];

  XCTAssertTrue(upgrade.cancelled);
  XCTAssertEqual(_loader.loads.count, 3u, @"the new source's load");
}

- (void)testRecyclingTheViewCancelsAnUpgrade {
  [self showLoadedImage];
  [self resize:CGSizeMake(200, 200)];

  [_view prepareForRecycle];

  XCTAssertTrue(_loader.loads[1].cancelled);
}

#pragma mark Helpers

/// A 100×100 pt view showing its image, decoded for that size.
- (void)showLoadedImage {
  [self showLoadedImageOfPixels:[self pixels:CGSizeMake(100, 100)]];
}

- (void)showLoadedImageOfPixels:(CGSize)pixels {
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  XCTAssertEqual(_loader.loads.count, 1u);
  [_loader.loads[0] succeedWithPixels:pixels];
}

- (CGSize)pixels:(CGSize)points {
  return CGSizeMake(points.width * _scale, points.height * _scale);
}

/// A transaction that changes props, in Fabric's order: props, then the
/// frame (unchanged here), then `finalizeUpdates:`, where a load starts.
- (void)setProps:(void (^)(TurboImageViewProps &props))change {
  auto next = std::make_shared<TurboImageViewProps>(_props ? *_props : TurboImageViewProps{});
  change(*next);
  [_view updateProps:next oldProps:_props];
  _props = next;
  [_view finalizeUpdates:RNComponentViewUpdateMaskProps];
}

- (void)setSource:(NSString *)uri {
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(uri.UTF8String);
  }];
}

/// What Fabric does when layout gives the view a new frame.
- (void)resize:(CGSize)size {
  LayoutMetrics next = _layout;
  next.frame.size = {size.width, size.height};
  next.displayType = DisplayType::Flex;
  [_view updateLayoutMetrics:next oldLayoutMetrics:_layout];
  _layout = next;
  [_view finalizeUpdates:RNComponentViewUpdateMaskLayoutMetrics];
}

- (nullable UIImage *)imageOnScreen {
  for (UIView *subview in _view.subviews) {
    if ([subview isKindOfClass:UIImageView.class]) {
      return ((UIImageView *)subview).image;
    }
  }
  return nil;
}

@end
