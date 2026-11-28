// `TurboImageComponentView` with a fake loader and the real core: when it
// loads and what it asks for. iOS twin of TurboImageViewTest.kt. Driven in
// Fabric's order (props, layout, finalizeUpdates); no event emitter, so
// events are covered elsewhere.
// TODO: hash placeholders, `recyclingKey` and Live Text.

#import <XCTest/XCTest.h>

#import <React/RCTBridgeModule.h>
#import <React/RCTComponentViewProtocol.h>
#import <React/RCTUtils.h>
#import <TurboImage/TIImageLoaderRegistry+Testing.h>
#import <react/renderer/components/TurboImageSpec/Props.h>

using namespace facebook::react;

/// The cache module's `prefetch` (its class is private to the pod).
@interface NSObject (TIPrefetching)
- (void)prefetch:(NSArray *)sources
     cachePolicy:(NSString *)cachePolicy
         resolve:(RCTPromiseResolveBlock)resolve
          reject:(RCTPromiseRejectBlock)reject;
@end

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

/// Calls back despite a cancel (forbidden); the view must ignore it.
- (void)deliverDespiteCancelWithPixels:(CGSize)pixels {
  _cancelled = NO;
  [self succeedWithPixels:pixels];
  _cancelled = YES;
}

- (void)fail {
  [self failWithCode:TIImageLoadErrorNetwork];
}

- (void)failWithCode:(TIImageLoadErrorCode)code {
  NSAssert(!_cancelled, @"a cancelled load cannot fail");
  _completion(nil, nil, NO, [NSError errorWithDomain:TIImageLoadErrorDomain code:code userInfo:nil]);
}

@end

/// The tests' sources all live here; see `-[TIFakeLoader loads]`.
static NSString *const kTestHost = @"images.example.com";

/// Loads finish when the test says so; never after a cancel.
@interface TIFakeLoader : NSObject <TIImageLoading>
/// Loads of the tests' own sources (`kTestHost`). The host app's views share
/// the registry and see the tests' app-state notifications too: on a cold
/// install without the fixture server, the Home screen's image has failed
/// with `network` by the first test, and retries on each return to the
/// foreground. Those loads are taken but never recorded or finished.
@property(nonatomic, readonly) NSMutableArray<TIFakeLoad *> *loads;
/// What the cache module asked to prefetch. Never completed.
@property(nonatomic, readonly) NSMutableArray<TIImageRequest *> *prefetches;
@end

@implementation TIFakeLoader

- (instancetype)init {
  if ((self = [super init])) {
    _loads = [NSMutableArray new];
    _prefetches = [NSMutableArray new];
  }
  return self;
}

- (id<TIImageLoadTask>)loadImageWithRequest:(TIImageRequest *)request
                                   progress:(TIImageLoadProgress)progress
                                 completion:(TIImageLoadCompletion)completion {
  TIFakeLoad *load = [[TIFakeLoad alloc] initWithRequest:request completion:completion];
  if ([request.url.host isEqualToString:kTestHost]) {
    [_loads addObject:load];
  }
  return load;
}

- (UIImageView *)makeImageView {
  return [UIImageView new];
}

- (void)displayImage:(UIImage *)image animation:(id)animation inImageView:(UIImageView *)imageView {
  imageView.image = image;
}

- (id<TIImageLoadTask>)prefetchRequest:(TIImageRequest *)request completion:(void (^)(BOOL))completion {
  [_prefetches addObject:request];
  return [[TIFakeLoad alloc] initWithRequest:request completion:^(UIImage *, id, BOOL, NSError *) {}];
}
- (id<TIImageLoadTask>)imageSizeForRequest:(TIImageRequest *)request
                                completion:(void (^)(CGSize, NSError *))completion {
  return [[TIFakeLoad alloc] initWithRequest:request completion:^(UIImage *, id, BOOL, NSError *) {}];
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
  // Swap out the app's Nuke adapter; the view reads the registry each load.
  _previousLoader = TIImageLoaderRegistry.sharedLoader;
  _loader = [TIFakeLoader new];
  [TIImageLoaderRegistry setSharedLoaderForTesting:_loader];
  _view = [[NSClassFromString(@"TurboImageComponentView") alloc] initWithFrame:CGRectZero];
  XCTAssertNotNil(_view);
  _layout = EmptyLayoutMetrics;
  _scale = RCTScreenScale();
}

- (void)tearDown {
  // Reset the view as Fabric does on reuse, so a failure it was left with
  // is forgotten: it still observes app-state notifications, and would
  // otherwise retry through the next test's fake loader.
  [_view prepareForRecycle];
  _view = nil;
  [TIImageLoaderRegistry setSharedLoaderForTesting:_previousLoader];
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
  // Smaller than the view means it's already the original size.
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
  // The player sizes frames itself; a swap would restart it.
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

- (void)testRecyclingTheViewStopsAFadeInProgress {
  // Reused within the fade, the view must not keep dissolving from the
  // previous row's snapshot over its next image.
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [_loader.loads[0] succeedWithPixels:[self pixels:CGSizeMake(100, 100)]];
  XCTAssertGreaterThan([self imageView].layer.animationKeys.count, 0u, @"the image fades in");

  [_view prepareForRecycle];

  XCTAssertEqual([self imageView].layer.animationKeys.count, 0u);
}

- (void)testRecyclingTheViewCancelsAnUpgrade {
  [self showLoadedImage];
  [self resize:CGSizeMake(200, 200)];

  [_view prepareForRecycle];

  XCTAssertTrue(_loader.loads[1].cancelled);
}

#pragma mark Image placeholders

static NSString *const kThumbURL = @"https://images.example.com/photos/harbour-thumb.jpg";

/// A 100 pt view loading `kURL` with `kThumbURL` as its placeholder.
- (void)setSourceWithThumbnail {
  [self resize:CGSizeMake(100, 100)];
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(kURL.UTF8String);
    props.placeholder.uri = std::string(kThumbURL.UTF8String);
  }];
}

- (nullable TIFakeLoad *)loadOf:(NSString *)url {
  for (TIFakeLoad *load in _loader.loads) {
    if ([load.request.url.absoluteString isEqualToString:url]) {
      return load;
    }
  }
  return nil;
}

- (void)testAnImagePlaceholderShowsWhileTheImageLoads {
  [self setSourceWithThumbnail];
  TIFakeLoad *thumb = [self loadOf:kThumbURL];
  XCTAssertNotNil(thumb, @"the placeholder loads beside the image");
  XCTAssertNotNil([self loadOf:kURL]);

  [thumb succeedWithPixels:CGSizeMake(10, 10)];

  XCTAssertTrue(CGSizeEqualToSize([self imageOnScreen].size, CGSizeMake(10, 10)));

  [[self loadOf:kURL] succeedWithPixels:[self pixels:CGSizeMake(100, 100)]];

  XCTAssertTrue(CGSizeEqualToSize([self imageOnScreen].size, [self pixels:CGSizeMake(100, 100)]));
}

- (void)testAPlaceholderThatArrivesLateIsNotShownOverTheImage {
  [self setSourceWithThumbnail];
  TIFakeLoad *thumb = [self loadOf:kThumbURL];
  [[self loadOf:kURL] succeedWithPixels:[self pixels:CGSizeMake(100, 100)]];

  // The image cancelled it; a loader that called back anyway must not win.
  XCTAssertTrue(thumb.cancelled, @"no longer needed");
  [thumb deliverDespiteCancelWithPixels:CGSizeMake(10, 10)];

  XCTAssertTrue(CGSizeEqualToSize([self imageOnScreen].size, [self pixels:CGSizeMake(100, 100)]));
}

// Only the placeholder changes, so no reload runs to re-apply it.
- (void)testANewPlaceholderUriAloneReplacesThePlaceholder {
  static NSString *const kOtherThumbURL = @"https://images.example.com/photos/harbour-thumb-2.jpg";
  [self setSourceWithThumbnail];
  TIFakeLoad *first = [self loadOf:kThumbURL];

  [self setProps:^(TurboImageViewProps &props) {
    props.placeholder.uri = std::string(kOtherThumbURL.UTF8String);
  }];

  XCTAssertTrue(first.cancelled, @"the old placeholder is no longer wanted");
  TIFakeLoad *second = [self loadOf:kOtherThumbURL];
  XCTAssertNotNil(second, @"the new placeholder loads");
  XCTAssertEqual(_loader.loads.count, 3u, @"the image's own load is not restarted");
  [second succeedWithPixels:CGSizeMake(12, 12)];
  XCTAssertTrue(CGSizeEqualToSize([self imageOnScreen].size, CGSizeMake(12, 12)));
}

// Only `showPlaceholderOnFailure` changes, after the failure: no reload runs.
- (void)testTurningOffShowPlaceholderOnFailureClearsTheKeptPlaceholder {
  [self resize:CGSizeMake(100, 100)];
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(kURL.UTF8String);
    props.placeholder.uri = std::string(kThumbURL.UTF8String);
    props.showPlaceholderOnFailure = true;
  }];
  [[self loadOf:kThumbURL] succeedWithPixels:CGSizeMake(10, 10)];
  [[self loadOf:kURL] failWithCode:TIImageLoadErrorDecode];
  XCTAssertNotNil([self imageOnScreen], @"kept over the failure");

  [self setProps:^(TurboImageViewProps &props) {
    props.showPlaceholderOnFailure = false;
  }];

  XCTAssertNil([self imageOnScreen]);
}

- (void)testTurningOnShowPlaceholderOnFailureShowsThePlaceholderOverTheFailure {
  [self setSourceWithThumbnail];
  [[self loadOf:kURL] failWithCode:TIImageLoadErrorDecode];
  XCTAssertNil([self imageOnScreen]);
  const NSUInteger loadsBefore = _loader.loads.count;

  [self setProps:^(TurboImageViewProps &props) {
    props.showPlaceholderOnFailure = true;
  }];

  XCTAssertEqual(_loader.loads.count, loadsBefore + 1, @"only the placeholder loads again");
  [_loader.loads.lastObject succeedWithPixels:CGSizeMake(10, 10)];
  XCTAssertTrue(CGSizeEqualToSize([self imageOnScreen].size, CGSizeMake(10, 10)));
}

- (void)testShowPlaceholderOnFailureMidLoadLeavesThePlaceholderLoadAlone {
  // The flag only decides what a failure shows; nothing to redo yet.
  [self setSourceWithThumbnail];
  TIFakeLoad *thumb = [self loadOf:kThumbURL];
  const NSUInteger loadsBefore = _loader.loads.count;

  [self setProps:^(TurboImageViewProps &props) {
    props.showPlaceholderOnFailure = true;
  }];

  XCTAssertEqual(_loader.loads.count, loadsBefore, @"no second placeholder load");
  XCTAssertFalse(thumb.cancelled);
  [thumb succeedWithPixels:CGSizeMake(10, 10)];
  XCTAssertTrue(CGSizeEqualToSize([self imageOnScreen].size, CGSizeMake(10, 10)));
}

- (void)testAnImagePlaceholderOnAnotherOriginGetsNoHeaders {
  // The source's credentials must not reach another origin. A port makes
  // one here, since the fake loader records only `kTestHost`'s loads.
  static NSString *const kOtherOriginThumbURL = @"https://images.example.com:8443/photos/harbour-thumb.jpg";
  [self resize:CGSizeMake(100, 100)];
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(kURL.UTF8String);
    props.source.headers = {{.name = "Authorization", .value = "Bearer t0ken"}};
    props.placeholder.uri = std::string(kOtherOriginThumbURL.UTF8String);
  }];

  TIFakeLoad *thumb = [self loadOf:kOtherOriginThumbURL];
  XCTAssertNotNil(thumb);
  XCTAssertEqual(thumb.request.headers.count, 0u);
  XCTAssertEqual([self loadOf:kURL].request.headers.count, 1u, @"the source keeps its headers");
}

- (void)testAnImagePlaceholderUsesTheSourcesHeadersAndNoProcessing {
  [self resize:CGSizeMake(100, 100)];
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(kURL.UTF8String);
    props.source.headers = {{.name = "Authorization", .value = "Bearer t0ken"}};
    props.blur = 8;
    props.placeholder.uri = std::string(kThumbURL.UTF8String);
  }];

  TIImageRequest *thumb = [self loadOf:kThumbURL].request;
  XCTAssertEqualObjects(thumb.headers, (@[ @[ @"Authorization", @"Bearer t0ken" ] ]));
  XCTAssertEqualObjects(thumb.processorKey, @"");
  XCTAssertNotEqualObjects([self loadOf:kURL].request.processorKey, @"");
}

#pragma mark Prefetching

/// A prefetch stores the original on disk, under the view's key.
- (void)testAPrefetchStoresTheOriginalOnDiskUnderTheViewsKey {
  id module = [NSClassFromString(@"TurboImageModule") new];
  [module prefetch:@[ @{@"uri" : kURL} ]
       cachePolicy:@"default"
           resolve:^(id) {}
            reject:^(NSString *, NSString *, NSError *) {}];
  XCTAssertEqual(_loader.prefetches.count, 1u);
  TIImageRequest *prefetched = _loader.prefetches[0];

  [self resize:CGSizeMake(300, 80)];
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(kURL.UTF8String);
    props.blur = 4;
  }];
  TIImageRequest *shown = _loader.loads[0].request;

  XCTAssertEqualObjects(prefetched.cacheKey, shown.cacheKey);
  XCTAssertTrue(prefetched.diskCacheWrite);
  XCTAssertFalse(prefetched.memoryCacheWrite, @"nothing is decoded");
  XCTAssertEqualObjects(prefetched.processorKey, @"");
  XCTAssertTrue(CGSizeEqualToSize(prefetched.decodeSize, CGSizeZero));
}

#pragma mark contentPosition and own-size modes

- (nullable UIImageView *)imageView {
  NSMutableArray<UIView *> *views = [_view.subviews mutableCopy];
  while (views.count > 0) {
    UIView *view = views.firstObject;
    [views removeObjectAtIndex:0];
    if ([view isKindOfClass:UIImageView.class]) {
      return (UIImageView *)view;
    }
    [views addObjectsFromArray:view.subviews];
  }
  return nil;
}

- (void)testAPositionedCoverDrawsInTheCoresRectangle {
  [self resize:CGSizeMake(200, 100)];
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(kURL.UTF8String);
    props.resizeMode = TurboImageViewResizeMode::Cover;
    props.contentPositionY = 1;  // bottom
  }];

  // 50x50 covering 200x100: 200x200, its bottom 100 shown.
  [_loader.loads[0] succeedWithPixels:CGSizeMake(50, 50)];

  XCTAssertTrue(CGRectEqualToRect([self imageView].frame, CGRectMake(0, -100, 200, 200)));
}

- (void)testCenterDrawsABitmapAtItsPixelsOverTheScreenScale {
  // 150 px drawn as 150 px (like Android), not 150 points.
  [self resize:CGSizeMake(200, 100)];
  [self setProps:^(TurboImageViewProps &props) {
    props.source.uri = std::string(kURL.UTF8String);
    props.resizeMode = TurboImageViewResizeMode::Center;
  }];

  [_loader.loads[0] succeedWithPixels:CGSizeMake(150, 150)];

  const CGFloat side = 150 / _scale;
  XCTAssertTrue(CGRectEqualToRect([self imageView].frame,
                                  CGRectMake((200 - side) / 2, (100 - side) / 2, side, side)));
}

#pragma mark Retry after a network failure

- (void)testANetworkFailureRetriesWhenTheAppReturns {
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [_loader.loads[0] fail];

  [self enterBackground];
  XCTAssertEqual(_loader.loads.count, 1u, @"nothing retries in the background");
  [self enterForeground];

  XCTAssertEqual(_loader.loads.count, 2u);
  XCTAssertEqualObjects(_loader.loads[1].request.url, _loader.loads[0].request.url);
  [_loader.loads[1] succeedWithPixels:[self pixels:CGSizeMake(100, 100)]];
  XCTAssertNotNil([self imageOnScreen]);
}

- (void)testOtherFailuresAreNotRetried {
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [_loader.loads[0] failWithCode:TIImageLoadErrorDecode];

  [self enterBackground];
  [self enterForeground];

  XCTAssertEqual(_loader.loads.count, 1u);
}

- (void)testAMissingLocalFileIsNotRetried {
  // The adapter reports a file it cannot read as `network`; no return to
  // the app brings it back.
  // `kTestHost` as the file URL's host, so the fake loader records it.
  [self resize:CGSizeMake(100, 100)];
  [self setSource:[NSString stringWithFormat:@"file://%@/missing/photo.jpg", kTestHost]];
  [_loader.loads[0] fail];

  [self enterBackground];
  [self enterForeground];

  XCTAssertEqual(_loader.loads.count, 1u);
}

- (void)testALoadCutOffByTheBackgroundRetriesAsSoonAsItFails {
  // iOS reports the dropped connection only after the app is back.
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [self enterBackground];
  [self enterForeground];
  XCTAssertEqual(_loader.loads.count, 1u, @"still in flight: nothing to retry");

  [_loader.loads[0] fail];

  XCTAssertEqual(_loader.loads.count, 2u);
}

- (void)testALoadStartedInTheBackgroundRetriesWhenCutOffAfterTheReturn {
  // The app keeps running for a few seconds after it leaves the screen, so
  // a source can arrive then; the suspension that follows cuts its load.
  [self resize:CGSizeMake(100, 100)];
  [self enterBackground];
  [self setSource:kURL];
  [self enterForeground];
  XCTAssertEqual(_loader.loads.count, 1u, @"still in flight: nothing to retry");

  [_loader.loads[0] fail];

  XCTAssertEqual(_loader.loads.count, 2u);
}

- (void)testALoadThatFailsInTheBackgroundWaitsForTheForeground {
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [self enterBackground];
  [_loader.loads[0] fail];
  XCTAssertEqual(_loader.loads.count, 1u);

  [self enterForeground];

  XCTAssertEqual(_loader.loads.count, 2u);
}

- (void)testAFailedRetryWaitsForTheNextReturn {
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [_loader.loads[0] fail];
  [self enterBackground];
  [self enterForeground];

  [_loader.loads[1] fail];
  XCTAssertEqual(_loader.loads.count, 2u, @"no retry loop");

  [self enterBackground];
  [self enterForeground];
  XCTAssertEqual(_loader.loads.count, 3u);
}

- (void)testANewSourceForgetsTheFailure {
  [self resize:CGSizeMake(100, 100)];
  [self setSource:kURL];
  [_loader.loads[0] fail];
  [self setSource:kThumbURL];
  [_loader.loads[1] failWithCode:TIImageLoadErrorDecode];

  [self enterBackground];
  [self enterForeground];

  XCTAssertEqual(_loader.loads.count, 2u);
}

#pragma mark Helpers

- (void)enterBackground {
  [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification
                                                    object:nil];
}

- (void)enterForeground {
  [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillEnterForegroundNotification
                                                    object:nil];
}

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

/// A props transaction in Fabric's order: props, frame, finalizeUpdates.
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

// The image view sits inside the content view's clipping container.
- (nullable UIImage *)imageOnScreen {
  NSMutableArray<UIView *> *views = [_view.subviews mutableCopy];
  while (views.count > 0) {
    UIView *view = views.firstObject;
    [views removeObjectAtIndex:0];
    if ([view isKindOfClass:UIImageView.class]) {
      return ((UIImageView *)view).image;
    }
    [views addObjectsFromArray:view.subviews];
  }
  return nil;
}

@end
