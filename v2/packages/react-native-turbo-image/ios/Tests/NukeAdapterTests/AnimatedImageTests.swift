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
  let adapter = Adapter()

  // MARK: What a load delivers

  @Test func animatedImageArrivesAsAStillWithAnAnimation() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.gif(), decodeSize: CGSize(width: 20, height: 15)))

    let image = try #require(loaded.image)
    // The still is one frame, decoded for the view like any other image.
    #expect(image.images == nil)
    #expect(image.size.width * image.scale <= 20)
    #expect(loaded.animation != nil)
  }

  @Test func stillImageHasNoAnimation() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.png()))

    #expect(loaded.image != nil)
    #expect(loaded.animation == nil)
  }

  /// Processors apply to the still (ADR 0007). Kept, the animation would
  /// play the unprocessed frames over the processed first frame.
  @Test func processedAnimationIsAStill() async throws {
    let loaded = await adapter.load(
      adapter.request(for: try Fixture.gif(), processorKey: "identity", processor: { $0 }))

    #expect(loaded.image != nil)
    #expect(loaded.animation == nil)
  }

  @Test func animationSurvivesTheMemoryCache() async throws {
    let request = adapter.request(for: try Fixture.gif(), decodeSize: CGSize(width: 20, height: 15))
    let first = await adapter.load(request)
    let second = await adapter.load(request)

    #expect(!first.fromMemoryCache)
    #expect(second.fromMemoryCache)
    #expect(second.animation != nil)
  }

  // MARK: What the view shows

  @Test func displayPlaysTheAnimationInTheLoadersView() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.gif()))
    let view = try adapter.animatedView()

    adapter.loader.display(try #require(loaded.image), animation: loaded.animation, in: view)

    #expect(view.image != nil)
    #expect(view.animation != nil)
  }

  /// A view recycled while it was playing: the Fabric view clears it with
  /// `image = nil`, and whatever the next component shows must not have the
  /// old animation painting over it.
  @Test func clearingTheImageStopsTheAnimation() async throws {
    let animated = await adapter.load(adapter.request(for: try Fixture.gif()))
    let still = await adapter.load(adapter.request(for: try Fixture.png()))
    let view = try adapter.animatedView()
    adapter.loader.display(try #require(animated.image), animation: animated.animation, in: view)

    view.image = nil

    #expect(view.animation == nil)
    #expect(view.image == nil)

    // The next life of the view: a still.
    let stillImage = try #require(still.image)
    adapter.loader.display(stillImage, animation: still.animation, in: view)

    #expect(view.animation == nil)
    #expect(view.image === stillImage)
  }

  /// A mounted view whose source changes from an animation to a still: the
  /// animation stays on screen until the still has loaded (the lifecycle's
  /// rule), and then has to go.
  @Test func aStillReplacesAPlayingAnimation() async throws {
    let animated = await adapter.load(adapter.request(for: try Fixture.gif()))
    let still = await adapter.load(adapter.request(for: try Fixture.png()))
    let view = try adapter.animatedView()
    adapter.loader.display(try #require(animated.image), animation: animated.animation, in: view)

    let stillImage = try #require(still.image)
    adapter.loader.display(stillImage, animation: still.animation, in: view)

    #expect(view.animation == nil)
    #expect(view.image === stillImage)
  }

  /// The other direction: a view that showed a still, recycled or not, plays
  /// the animation it is given next.
  @Test func anAnimationReplacesAStill() async throws {
    let animated = await adapter.load(adapter.request(for: try Fixture.gif()))
    let still = await adapter.load(adapter.request(for: try Fixture.png()))
    let view = try adapter.animatedView()
    adapter.loader.display(try #require(still.image), animation: still.animation, in: view)
    #expect(view.animation == nil)

    adapter.loader.display(try #require(animated.image), animation: animated.animation, in: view)

    #expect(view.animation != nil)
  }

  /// A placeholder is a plain `image` set by the Fabric view, like a clear.
  @Test func aPlaceholderStopsTheAnimation() async throws {
    let animated = await adapter.load(adapter.request(for: try Fixture.gif()))
    let view = try adapter.animatedView()
    adapter.loader.display(try #require(animated.image), animation: animated.animation, in: view)

    let placeholder = UIImage()
    view.image = placeholder

    #expect(view.animation == nil)
    #expect(view.image === placeholder)
  }

  /// The registry's loader can be replaced while views exist, so `display`
  /// can be handed a view this loader did not make.
  @Test func aViewTheLoaderDidNotMakeGetsTheStill() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.gif()))
    let view = UIImageView()
    let image = try #require(loaded.image)

    adapter.loader.display(image, animation: loaded.animation, in: view)

    #expect(view.image === image)
  }

  // MARK: How it plays

  /// Android's animated drawables loop whatever the file says; Nuke's default
  /// would follow the file and play a GIF without a loop count once.
  @Test func animationsLoopForever() throws {
    #expect(try adapter.animatedView().playerOptions.loopCount == .infinite)
  }

  /// Frames follow the rule the still was decoded by: for the view, unless
  /// the request asked for the image at its own size (`allowDownscaling` off).
  @Test func framesAreSizedLikeTheStill() async throws {
    let gif = try Fixture.gif()
    let fitted = await adapter.load(adapter.request(for: gif, decodeSize: CGSize(width: 20, height: 15)))
    let original = await adapter.load(adapter.request(for: gif, decodeSize: .zero))
    let view = try adapter.animatedView()

    adapter.loader.display(try #require(fitted.image), animation: fitted.animation, in: view)
    #expect(view.isAutomaticDownsamplingEnabled)

    adapter.loader.display(try #require(original.image), animation: original.animation, in: view)
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
    let loaded = await adapter.loadTogether([
      adapter.request(for: gif, cacheKey: key, decodeSize: CGSize(width: 30, height: 30)),
      adapter.request(for: gif, cacheKey: key, decodeSize: CGSize(width: 10, height: 10)),
    ])
    let (loadedLarge, loadedSmall) = (loaded[0], loaded[1])
    let (largeView, smallView) = (try adapter.animatedView(), try adapter.animatedView())

    adapter.loader.display(try #require(loadedLarge.image), animation: loadedLarge.animation, in: largeView)
    adapter.loader.display(try #require(loadedSmall.image), animation: loadedSmall.animation, in: smallView)

    let animation = try #require(largeView.animation)
    #expect(animation === smallView.animation)
  }

  /// What a key names can change (disposed of and fetched again, or
  /// revalidated under `urlCache`); the old animation must not stand in.
  @Test func aKeyWhoseBytesChangedGetsANewAnimation() async throws {
    let key = UUID().uuidString
    let first = await adapter.load(adapter.request(for: try Fixture.gif(frames: 2), cacheKey: key, memoryCacheRead: false))
    let second = await adapter.load(adapter.request(for: try Fixture.gif(frames: 3), cacheKey: key, memoryCacheRead: false))
    let (firstView, secondView) = (try adapter.animatedView(), try adapter.animatedView())

    adapter.loader.display(try #require(first.image), animation: first.animation, in: firstView)
    adapter.loader.display(try #require(second.image), animation: second.animation, in: secondView)

    #expect(firstView.animation?.frameCount == 2)
    #expect(secondView.animation?.frameCount == 3)
  }
}
