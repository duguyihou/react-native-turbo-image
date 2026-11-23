// Animated images through the Nuke adapter, end to end: a real GIF loaded
// through `TIImageLoading` and shown in the image view the adapter supplies.
//
// Why these are native tests: nothing reports to JS whether an image is
// animating, so the on-device smoke suite cannot see any of this. What it
// leaves out is exactly what goes wrong unnoticed: an animation that keeps
// painting frames into a view that has moved on to another image (a recycled
// list cell), or one that silently became a still.
//
// The tests ask the image view whether it has an animation to play. That is
// the state everything else follows from: NukeUI's `AnimatedImageView` only
// paints frames of the animation it holds. Whether frames then reach the
// screen needs a window and a display link, and is NukeUI's own business.
//
// Not covered here: the Fabric view (`TurboImageComponentView`), which this
// package cannot build without a React Native app. What it does on a recycle
// is decided by the core's lifecycle (`ClearImage`, tested in C++) and carried
// out as `imageView.image = nil`, which `clearingTheImageStopsTheAnimation`
// performs on the same view class.

import ImageIO
import NukeUI
import Testing
import TurboImageLoaderAPI
import UIKit
import UniformTypeIdentifiers

@testable import TurboImageNuke

@MainActor
@Suite(.serialized)
struct AnimatedImageTests {
  let loader = NukeImageLoader()

  // MARK: What a load delivers

  @Test func animatedImageArrivesAsAStillWithAnAnimation() async throws {
    let loaded = await load(request(for: try Fixture.gif(), decodeSize: CGSize(width: 20, height: 15)))

    let image = try #require(loaded.image)
    // The still is one frame, decoded for the view like any other image.
    #expect(image.images == nil)
    #expect(image.size.width * image.scale <= 20)
    #expect(loaded.animation != nil)
  }

  @Test func stillImageHasNoAnimation() async throws {
    let loaded = await load(request(for: try Fixture.png()))

    #expect(loaded.image != nil)
    #expect(loaded.animation == nil)
  }

  /// Processors apply to the still (ADR 0007). Kept, the animation would
  /// play the unprocessed frames over the processed first frame.
  @Test func processedAnimationIsAStill() async throws {
    let loaded = await load(
      request(for: try Fixture.gif(), processorKey: "identity", processor: { $0 }))

    #expect(loaded.image != nil)
    #expect(loaded.animation == nil)
  }

  @Test func animationSurvivesTheMemoryCache() async throws {
    let request = request(for: try Fixture.gif(), decodeSize: CGSize(width: 20, height: 15))
    let first = await load(request)
    let second = await load(request)

    #expect(!first.fromMemoryCache)
    #expect(second.fromMemoryCache)
    #expect(second.animation != nil)
  }

  // MARK: What the view shows

  @Test func displayPlaysTheAnimationInTheLoadersView() async throws {
    let loaded = await load(request(for: try Fixture.gif()))
    let view = try animatedView()

    loader.display(try #require(loaded.image), animation: loaded.animation, in: view)

    #expect(view.image != nil)
    #expect(view.animation != nil)
  }

  /// A view recycled while it was playing: the Fabric view clears it with
  /// `image = nil`, and whatever the next component shows must not have the
  /// old animation painting over it.
  @Test func clearingTheImageStopsTheAnimation() async throws {
    let animated = await load(request(for: try Fixture.gif()))
    let still = await load(request(for: try Fixture.png()))
    let view = try animatedView()
    loader.display(try #require(animated.image), animation: animated.animation, in: view)

    view.image = nil

    #expect(view.animation == nil)
    #expect(view.image == nil)

    // The next life of the view: a still.
    let stillImage = try #require(still.image)
    loader.display(stillImage, animation: still.animation, in: view)

    #expect(view.animation == nil)
    #expect(view.image === stillImage)
  }

  /// A mounted view whose source changes from an animation to a still: the
  /// animation stays on screen until the still has loaded (the lifecycle's
  /// rule), and then has to go.
  @Test func aStillReplacesAPlayingAnimation() async throws {
    let animated = await load(request(for: try Fixture.gif()))
    let still = await load(request(for: try Fixture.png()))
    let view = try animatedView()
    loader.display(try #require(animated.image), animation: animated.animation, in: view)

    let stillImage = try #require(still.image)
    loader.display(stillImage, animation: still.animation, in: view)

    #expect(view.animation == nil)
    #expect(view.image === stillImage)
  }

  /// The other direction: a view that showed a still, recycled or not, plays
  /// the animation it is given next.
  @Test func anAnimationReplacesAStill() async throws {
    let animated = await load(request(for: try Fixture.gif()))
    let still = await load(request(for: try Fixture.png()))
    let view = try animatedView()
    loader.display(try #require(still.image), animation: still.animation, in: view)
    #expect(view.animation == nil)

    loader.display(try #require(animated.image), animation: animated.animation, in: view)

    #expect(view.animation != nil)
  }

  /// A placeholder is a plain `image` set by the Fabric view, like a clear.
  @Test func aPlaceholderStopsTheAnimation() async throws {
    let animated = await load(request(for: try Fixture.gif()))
    let view = try animatedView()
    loader.display(try #require(animated.image), animation: animated.animation, in: view)

    let placeholder = UIImage()
    view.image = placeholder

    #expect(view.animation == nil)
    #expect(view.image === placeholder)
  }

  /// The registry's loader can be replaced while views exist, so `display`
  /// can be handed a view this loader did not make.
  @Test func aViewTheLoaderDidNotMakeGetsTheStill() async throws {
    let loaded = await load(request(for: try Fixture.gif()))
    let view = UIImageView()
    let image = try #require(loaded.image)

    loader.display(image, animation: loaded.animation, in: view)

    #expect(view.image === image)
  }

  // MARK: How it plays

  /// Android's animated drawables loop whatever the file says; Nuke's default
  /// would follow the file and play a GIF without a loop count once.
  @Test func animationsLoopForever() throws {
    #expect(try animatedView().playerOptions.loopCount == .infinite)
  }

  /// Frames follow the rule the still was decoded by: for the view, unless
  /// the request asked for the image at its own size (`allowDownscaling` off).
  @Test func framesAreSizedLikeTheStill() async throws {
    let gif = try Fixture.gif()
    let fitted = await load(request(for: gif, decodeSize: CGSize(width: 20, height: 15)))
    let original = await load(request(for: gif, decodeSize: .zero))
    let view = try animatedView()

    loader.display(try #require(fitted.image), animation: fitted.animation, in: view)
    #expect(view.isAutomaticDownsamplingEnabled)

    loader.display(try #require(original.image), animation: original.animation, in: view)
    #expect(!view.isAutomaticDownsamplingEnabled)
  }

  /// Nuke shares decoded frames between views by the identity of the
  /// animation. Each view size is its own decode and memory-cache entry, and
  /// must still get the one animation of its image (`AnimationSources`).
  @Test func twoSizesOfOneImageShareOneAnimation() async throws {
    let gif = try Fixture.gif()
    let key = UUID().uuidString
    // Started together, as two views mounted in one transaction are: both
    // decodes are in flight before either has an animation to share.
    let loaded = await loadTogether([
      request(for: gif, cacheKey: key, decodeSize: CGSize(width: 30, height: 30)),
      request(for: gif, cacheKey: key, decodeSize: CGSize(width: 10, height: 10)),
    ])
    let (loadedLarge, loadedSmall) = (loaded[0], loaded[1])
    let (largeView, smallView) = (try animatedView(), try animatedView())

    loader.display(try #require(loadedLarge.image), animation: loadedLarge.animation, in: largeView)
    loader.display(try #require(loadedSmall.image), animation: loadedSmall.animation, in: smallView)

    let animation = try #require(largeView.animation)
    #expect(animation === smallView.animation)
  }

  /// What a key names can change (disposed of and fetched again, or
  /// revalidated under `urlCache`); the old animation must not stand in.
  @Test func aKeyWhoseBytesChangedGetsANewAnimation() async throws {
    let key = UUID().uuidString
    let first = await load(request(for: try Fixture.gif(frames: 2), cacheKey: key, memoryCacheRead: false))
    let second = await load(request(for: try Fixture.gif(frames: 3), cacheKey: key, memoryCacheRead: false))
    let (firstView, secondView) = (try animatedView(), try animatedView())

    loader.display(try #require(first.image), animation: first.animation, in: firstView)
    loader.display(try #require(second.image), animation: second.animation, in: secondView)

    #expect(firstView.animation?.frameCount == 2)
    #expect(secondView.animation?.frameCount == 3)
  }

  // MARK: - Helpers

  /// What a completion delivered. `@unchecked Sendable` only to cross the
  /// continuation: the seam completes on the main thread and every test
  /// runs on the main actor, so it never leaves it.
  private struct Loaded: @unchecked Sendable {
    let image: UIImage?
    let animation: Any?
    let fromMemoryCache: Bool
    let error: NSError?
  }

  private func load(_ request: TIImageRequest) async -> Loaded {
    await loadTogether([request])[0]
  }

  /// Starts every load before waiting for any, and returns their results in
  /// the order of `requests`.
  private func loadTogether(_ requests: [TIImageRequest]) async -> [Loaded] {
    final class Results {
      var loaded: [Loaded?]
      init(count: Int) { loaded = Array(repeating: nil, count: count) }
    }
    let results = Results(count: requests.count)
    return await withCheckedContinuation { continuation in
      for (index, request) in requests.enumerated() {
        _ = loader.loadImage(with: request, progress: nil) { image, animation, fromMemoryCache, error in
          results.loaded[index] = Loaded(
            image: image, animation: animation, fromMemoryCache: fromMemoryCache, error: error as NSError?)
          let finished = results.loaded.compactMap { $0 }
          if finished.count == requests.count {
            continuation.resume(returning: finished)
          }
        }
      }
    }
  }

  /// The loader's own image view, with a size: a view without one has
  /// nothing to decode frames for yet.
  private func animatedView() throws -> AnimatedImageView {
    let view = try #require(loader.makeImageView() as? AnimatedImageView)
    view.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
    return view
  }

  /// A request as the core resolves one for a local file: memory tier only.
  private func request(
    for file: URL,
    cacheKey: String = UUID().uuidString,
    decodeSize: CGSize = .zero,
    memoryCacheRead: Bool = true,
    processorKey: String = "",
    processor: TIImageProcessor? = nil
  ) -> TIImageRequest {
    TIImageRequest(
      url: file, cacheKey: cacheKey,
      memoryCacheRead: memoryCacheRead, memoryCacheWrite: true,
      diskCacheRead: false, diskCacheWrite: false, allowNetwork: true,
      processorKey: processorKey, processor: processor, headers: [], httpCache: false,
      decode: decodeSize, decodeFill: false,
      vectorDecode: decodeSize, vectorDecodeFill: false, displayScale: 1)
  }
}

/// Images written with ImageIO, so the tests need no files of their own.
private enum Fixture {
  struct Failure: Error {}

  static func gif(frames: Int = 3) throws -> URL {
    let url = temporaryFile("gif")
    let destination = try unwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil))
    // An explicit loop count ("forever"), as nearly every GIF has.
    CGImageDestinationSetProperties(
      destination,
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for index in 0..<frames {
      // A different picture per frame, or ImageIO may fold them into one.
      let frame = try unwrap(picture(shade: CGFloat(index + 1) / CGFloat(frames + 1)).cgImage)
      CGImageDestinationAddImage(
        destination, frame,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw Failure() }
    return url
  }

  static func png() throws -> URL {
    let url = temporaryFile("png")
    try unwrap(picture(shade: 0.5).pngData()).write(to: url)
    return url
  }

  private static func picture(shade: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
      UIColor(white: shade, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
      UIColor.red.setFill()
      context.fill(CGRect(x: 40 * shade, y: 10, width: 6, height: 6))
    }
  }

  private static func temporaryFile(_ fileExtension: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("turboimage-test-\(UUID().uuidString)")
      .appendingPathExtension(fileExtension)
  }

  private static func unwrap<Value>(_ value: Value?) throws -> Value {
    guard let value else { throw Failure() }
    return value
  }
}
