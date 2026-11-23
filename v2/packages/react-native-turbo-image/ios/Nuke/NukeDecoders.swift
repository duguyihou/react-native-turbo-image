// Format decoders for the Nuke adapter: animated images and SVG.
//
// 1.x needed two pods (Gifu, APNGKit), a private-API SVG renderer and a
// `format` prop to pick one. 2.0 picks by content, on both platforms (Coil's
// decoder factories sniff too), so `format` is no longer needed:
//
//   * animated GIF, APNG and WebP: Nuke decodes the first frame as a still
//     and this file attaches the animation to it, which NukeUI's
//     `AnimatedImageView` plays (NukeImageLoader.swift, `display`),
//   * SVG: Apple's private CoreSVG, as in 1.x (a deliberate decision recorded
//     in docs/migration-plan.md: App Review risk accepted for 1.x parity),
//   * everything else: Nuke's default decoder.

import Foundation
import ImageIO
import Nuke
import UIKit

enum TurboImageDecoders {
  /// `ImagePipeline.Configuration.makeImageDecoder`.
  ///
  /// Nuke creates a task's decoder once, lazily, usually from the *first
  /// chunk* of partial data, and then reuses it for the completed data
  /// (`TaskFetchOriginalImage.getDecoder`). So the format cannot be chosen
  /// here: a partial SVG would get Nuke's bitmap decoder for good. Every task
  /// gets a dispatcher instead, which decides on the complete bytes.
  static func make(_ context: ImageDecodingContext, animations: AnimationSources) -> (any ImageDecoding)? {
    ContentDecoder(
      fallback: ImageDecoders.Default(context: context),
      // The adapter sets `imageID` to the request's cache key.
      cacheKey: context.request.imageID,
      animations: animations)
  }
}

/// Picks a decoder by content once the data is complete; previews of partial
/// data (progressive JPEG and the like) stay with Nuke's default decoder.
struct ContentDecoder: ImageDecoding {
  /// Nuke's decoder for this context, if it recognised the data; it keeps
  /// the incremental state for previews, and the request's `thumbnail`.
  let fallback: ImageDecoders.Default?
  let cacheKey: String?
  let animations: AnimationSources

  func decode(_ data: Data) throws -> ImageContainer {
    if SVGDecoder.isSVG(data) {
      return try SVGDecoder().decode(data)
    }
    // The still: the whole image, or the first frame of an animation, no
    // larger than the request's decode bound (`thumbnail`).
    var container = try (fallback ?? ImageDecoders.Default()).decode(data)
    if let animation = animations.source(in: data, cacheKey: cacheKey) {
      container.animation = animation
      // The bytes the animation plays from, which it shares; set here too so
      // the memory cache counts them (`ImageContainer.memoryCost`).
      container.data = animation.data
    }
    return container
  }

  func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
    fallback?.decodePartiallyDownloadedData(data)
  }
}

/// Nuke flags every completed decode as needing decompression
/// (`makeImageResponse`), and decompression redraws the image into a single
/// bitmap: the vector SVG image would be rasterised at its canvas size.
/// Everything else keeps Nuke's background decompression, which spares the
/// main thread the first draw.
final class TurboImagePipelineDelegate: ImagePipeline.Delegate {
  func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
    guard pipeline.configuration.isDecompressionEnabled else { return false }
    return response.container.type != SVGDecoder.assetType
  }
}

// MARK: - Animated images

/// Finds the animation in a complete image.
///
/// Nuke's default decoder can attach one itself
/// (`isAnimatedImageParsingEnabled`), but not the way TurboImage needs it:
///
///   * it attaches none to a request with `thumbnail` options, and every
///     TurboImage request that is decoded for its view has them. Left to
///     Nuke, only `allowDownscaling={false}` images would play. The reason
///     for Nuke's rule (frames at full size would undo the downscaling) does
///     not apply here: the image view decodes the frames for its own size.
///   * it also plays HEIC and AVIF sequences, which Android shows as stills.
///
/// So that parsing is off (NukeImageLoader.swift) and this does it instead.
///
/// It also hands out **one source per image**, which Nuke's parsing would
/// not. Nuke shares decoded frames between views by the identity of their
/// source, and TurboImage decodes an image once per view size (each size is
/// its own memory-cache entry). A source per decode would give two views of
/// one GIF at different sizes two sets of frames, two parses and two copies
/// of the encoded bytes.
final class AnimationSources: @unchecked Sendable {
  // ImageIO reports several images for TIFF, ICO and HEIC files too; only
  // the formats TurboImage documents as animated are animated.
  private static let animatedTypes: Set<String> = [
    "com.compuserve.gif", "public.png", "org.webmproject.webp",
  ]

  // The live source of each cache key. Weak: a source lasts as long as a
  // memory-cache entry or a playing view holds it, and this must not be
  // what keeps the encoded bytes of an evicted image alive. Decodes run on
  // Nuke's decoding queue, two at a time, hence the lock.
  private let lock = NSLock()
  private let live = NSMapTable<NSString, AnimatedImageSource>.strongToWeakObjects()

  /// Nil for a still, including a single-frame GIF and a plain PNG.
  func source(in data: Data, cacheKey: String?) -> AnimatedImageSource? {
    // A cheap look at the header first: `AnimatedImageSource` reads the
    // delay of every frame, which is wasted on a format that is not played.
    guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(imageSource) as String?,
      Self.animatedTypes.contains(type),
      CGImageSourceGetCount(imageSource) > 1
    else { return nil }

    guard let key = cacheKey.map({ $0 as NSString }) else {
      return AnimatedImageSource(data: data)
    }
    if let existing = existing(for: key, matching: data) {
      return existing
    }
    // Parsed outside the lock: it reads every frame's delay. Delays are
    // corrected the way browsers and Android's decoder do it: 10 ms or less
    // becomes 100 ms (many GIFs declare 0 and rely on it).
    guard let source = AnimatedImageSource(data: data) else { return nil }
    return lock.withLock {
      // Looked up again: two sizes of one image mounted together decode at
      // the same time, and both miss the first lookup. Whichever gets here
      // second takes the first one's source and drops its own.
      if let existing = live.object(forKey: key), existing.data == data {
        return existing
      }
      live.setObject(source, forKey: key)
      return source
    }
  }

  /// The bytes are compared, not only the key: what a key names can change
  /// (the image was disposed of and fetched again, or `urlCache` revalidated
  /// it), and the old animation must not stand in for the new image.
  private func existing(for key: NSString, matching data: Data) -> AnimatedImageSource? {
    guard let existing = lock.withLock({ live.object(forKey: key) }), existing.data == data else {
      return nil
    }
    return existing
  }
}

// MARK: - SVG (private CoreSVG)

struct SVGDecoder: ImageDecoding {
  static let assetType = AssetType(rawValue: "public.svg-image")

  /// Cheap content sniff: optional BOM, whitespace, XML declaration,
  /// comments or doctype, then an `<svg` element near the start.
  static func isSVG(_ data: Data) -> Bool {
    // Lossy on purpose: the 4096-byte cut can split a UTF-8 character, and a
    // strict decode would then fail for the whole prefix.
    let text = String(decoding: data.prefix(4096), as: UTF8.self)
    let trimmed = text.drop { $0 == "\u{FEFF}" || $0.isWhitespace }
    return trimmed.hasPrefix("<") && text.contains("<svg")
  }

  func decode(_ data: Data) throws -> ImageContainer {
    guard let image = CoreSVG.image(from: data) else {
      throw ImageDecodingError.unknown
    }
    return ImageContainer(image: image, type: Self.assetType, data: data)
  }
}

/// Where to draw a vector image when pixels are needed
/// (`TIImageRequest.vectorDecodeSize`). A vector `UIImage` is sharp at any
/// size while an image view draws it, but a processor works on a bitmap,
/// and the bitmap has to be made at the size it will be shown at.
struct VectorTarget: Sendable {
  /// In pixels. Zero: the image's own size. A zero height: width only.
  let size: CGSize
  let fill: Bool
  let displayScale: CGFloat

  private static let maxPixels: CGFloat = 4096

  /// `image` as a bitmap of the target's size, or nil if it has no area.
  func draw(_ image: UIImage) -> UIImage? {
    let canvas = image.size
    guard canvas.width > 0, canvas.height > 0 else { return nil }
    // Pixels per point of the canvas, and the scale the bitmap reports.
    // At its own size the image keeps its size in points, so `center`
    // draws it as large as the vector would be; fitted to a view it is
    // 1x, like the bitmaps Nuke decodes.
    let pixelsPerPoint: CGFloat
    let bitmapScale: CGFloat
    if size.width > 0 {
      let horizontal = size.width / canvas.width
      let vertical = size.height > 0 ? size.height / canvas.height : horizontal
      pixelsPerPoint = fill ? max(horizontal, vertical) : min(horizontal, vertical)
      bitmapScale = 1
    } else {
      pixelsPerPoint = max(displayScale, 1)
      bitmapScale = pixelsPerPoint
    }
    // A bitmap is bounded by its source; a vector is not. Covering a wide,
    // short view with a tall SVG would otherwise ask for a bitmap hundreds
    // of megabytes large. 4096 is Coil's default `maxBitmapSize`, so both
    // platforms stop at the same place.
    let largest = max(canvas.width, canvas.height) * pixelsPerPoint
    let capped = pixelsPerPoint * min(1, Self.maxPixels / largest)
    let pixels = CGSize(
      width: max((canvas.width * capped).rounded(), 1),
      height: max((canvas.height * capped).rounded(), 1))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let bitmap = UIGraphicsImageRenderer(size: pixels, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: pixels))
    }
    guard let cgImage = bitmap.cgImage else { return nil }
    return UIImage(cgImage: cgImage, scale: bitmapScale, orientation: .up)
  }
}

/// The 1.x approach (ios/CoreSVG.swift on main): CoreSVG's C functions via
/// dlsym, and UIKit's private `+[UIImage _imageWithCGSVGDocument:]`, which
/// returns a vector-backed UIImage that stays sharp at any size. Unlike 1.x,
/// every symbol is checked: if a future iOS removes one, SVGs fail with a
/// `decode` error instead of crashing on a nil function pointer.
private enum CoreSVG {
  private typealias CreateFromData = @convention(c) (CFData, CFDictionary?) -> OpaquePointer?
  private typealias Release = @convention(c) (OpaquePointer) -> Void
  private typealias GetCanvasSize = @convention(c) (OpaquePointer) -> CGSize
  private typealias ImageWithDocument = @convention(c) (AnyObject, Selector, OpaquePointer) -> UIImage?

  private struct Symbols: @unchecked Sendable {
    let create: CreateFromData
    let release: Release
    let canvasSize: GetCanvasSize
  }

  // Resolved once. `@unchecked Sendable`: C function pointers are immutable.
  private static let symbols: Symbols? = {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_NOW),
      let create = dlsym(handle, "CGSVGDocumentCreateFromData"),
      let release = dlsym(handle, "CGSVGDocumentRelease"),
      let canvasSize = dlsym(handle, "CGSVGDocumentGetCanvasSize")
    else { return nil }
    return Symbols(
      create: unsafeBitCast(create, to: CreateFromData.self),
      release: unsafeBitCast(release, to: Release.self),
      canvasSize: unsafeBitCast(canvasSize, to: GetCanvasSize.self))
  }()

  private static let imageSelector = NSSelectorFromString("_imageWithCGSVGDocument:")

  static func image(from data: Data) -> UIImage? {
    guard let symbols, UIImage.responds(to: imageSelector),
      let document = symbols.create(data as CFData, nil)
    else { return nil }
    // The UIImage retains the document it renders from; this +1 is ours.
    defer { symbols.release(document) }
    guard symbols.canvasSize(document) != .zero else { return nil }
    let implementation = UIImage.method(for: imageSelector)
    let makeImage = unsafeBitCast(implementation, to: ImageWithDocument.self)
    return makeImage(UIImage.self, imageSelector, document)
  }
}
