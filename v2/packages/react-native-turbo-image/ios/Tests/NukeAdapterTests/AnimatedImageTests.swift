// Animated GIFs through the adapter into its image view. Native tests because
// JS can't see whether an image animates (e.g. a stale animation on a recycled
// cell). They check the view's `animation`; the Fabric view is tested elsewhere.

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
    // The still is one frame, decoded for the view.
    #expect(image.images == nil)
    #expect(image.size.width * image.scale <= 20)
    #expect(loaded.animation != nil)
  }

  @Test func stillImageHasNoAnimation() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.png()))

    #expect(loaded.image != nil)
    #expect(loaded.animation == nil)
  }

  /// Processors apply to the still only, so the animation is dropped (ADR 0007).
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

  /// Recycling clears with `image = nil`; the old animation must stop.
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

  /// Displaying a still replaces a playing animation.
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

  /// And the other way round.
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

  /// The loader can be swapped while views exist, so it may get a foreign view.
  @Test func aViewTheLoaderDidNotMakeGetsTheStill() async throws {
    let loaded = await adapter.load(adapter.request(for: try Fixture.gif()))
    let view = UIImageView()
    let image = try #require(loaded.image)

    adapter.loader.display(image, animation: loaded.animation, in: view)

    #expect(view.image === image)
  }

  // MARK: How it plays

  /// Loop forever, like Android (Nuke would play a loop-less GIF once).
  @Test func animationsLoopForever() throws {
    #expect(try adapter.animatedView().playerOptions.loopCount == .infinite)
  }

  /// Frames are downsampled only when the still was.
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

  /// Nuke shares frames by animation identity, so every size of one image
  /// must get the same animation (`AnimationSources`).
  @Test func twoSizesOfOneImageShareOneAnimation() async throws {
    let gif = try Fixture.gif()
    let key = UUID().uuidString
    // Started together, so both decodes race.
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

  /// New bytes under the same key get a new animation.
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
