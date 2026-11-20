// Format decoders for the Nuke adapter: animated images and SVG.
//
// Nuke's default decoder shows only the first frame of a GIF/APNG/WebP and
// cannot decode SVG. 1.x filled the gap with two pods (Gifu, APNGKit) plus a
// private-API SVG renderer, and needed a `format` prop to pick one. 2.0 picks
// by content, on both platforms (Coil's decoder factories sniff too), so
// `format` is no longer needed:
//
//   * animated GIF, APNG and WebP: ImageIO, which decodes all three, into a
//     `UIImage.animatedImage` that UIImageView plays without extra views,
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
  /// here: a partial GIF would get Nuke's static decoder for good. Every task
  /// gets a dispatcher instead, which decides on the complete bytes.
  static func make(_ context: ImageDecodingContext) -> (any ImageDecoding)? {
    ContentDecoder(
      fallback: ImageDecoders.Default(context: context),
      bound: context.request.userInfo[DecodeBound.userInfoKey] as? DecodeBound)
  }
}

/// The request's decode bound in pixels (`TIImageRequest.decodeSize`), handed
/// to the decoders through `ImageRequest.userInfo`. A zero height means
/// "width only".
struct DecodeBound: Sendable {
  static let userInfoKey = ImageRequest.UserInfoKey("com.turboimage.decodeBound")

  let size: CGSize
  let fill: Bool

  /// How much an image of `width` × `height` pixels shrinks to meet the
  /// bound; 1 when it already does. Never above 1: decoding does not upscale.
  func scale(forWidth width: Int, height: Int) -> CGFloat {
    guard width > 0, height > 0, size.width > 0 else { return 1 }
    let horizontal = size.width / CGFloat(width)
    guard size.height > 0 else { return min(horizontal, 1) }
    let vertical = size.height / CGFloat(height)
    return min(fill ? max(horizontal, vertical) : min(horizontal, vertical), 1)
  }
}

/// Picks a decoder by content once the data is complete; previews of partial
/// data (progressive JPEG and the like) stay with Nuke's default decoder.
struct ContentDecoder: ImageDecoding {
  /// Nuke's decoder for this context, if it recognised the data; it keeps
  /// the incremental state for previews.
  let fallback: ImageDecoders.Default?
  /// Nil when the request asked for the original size.
  let bound: DecodeBound?

  func decode(_ data: Data) throws -> ImageContainer {
    if SVGDecoder.isSVG(data) {
      return try SVGDecoder().decode(data)
    }
    if AnimatedImageDecoder.isAnimated(data) {
      return try AnimatedImageDecoder(bound: bound).decode(data)
    }
    return try (fallback ?? ImageDecoders.Default()).decode(data)
  }

  func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
    fallback?.decodePartiallyDownloadedData(data)
  }
}

/// Nuke flags every completed decode as needing decompression
/// (`makeImageResponse`), and decompression redraws the image into a single
/// bitmap: an animated UIImage would lose its frames and the vector SVG image
/// would be rasterised at its canvas size. Everything else keeps Nuke's
/// background decompression, which spares the main thread the first draw.
final class TurboImagePipelineDelegate: ImagePipeline.Delegate {
  func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
    guard pipeline.configuration.isDecompressionEnabled else { return false }
    return response.image.images == nil && response.container.type != SVGDecoder.assetType
  }
}

// MARK: - Animated images

struct AnimatedImageDecoder: ImageDecoding {
  /// Frames are decoded no larger than the request's bound, like a still
  /// image (which Nuke's default decoder downscales from `thumbnail`).
  let bound: DecodeBound?

  /// Every frame is decoded up front (UIImageView needs them all), so an
  /// animation larger than this, at the size it is decoded at, is shown as
  /// its first frame instead.
  /// Android's AnimatedImageDrawable decodes frames lazily and has no such
  /// limit. TODO: a lazily decoding animated view would lift this.
  static let maxDecodedBytes = 64 * 1024 * 1024

  /// Uniform frame slots UIImage may expand variable delays into (see below).
  private static let maxExpandedFrames = 1000

  // ImageIO also reports several images for TIFF/ICO/HEIC sequences; only
  // the formats TurboImage documents as animated are animated.
  private static let animatedTypes: Set<String> = [
    "com.compuserve.gif", "public.png", "org.webmproject.webp",
  ]

  static func isAnimated(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let type = CGImageSourceGetType(source) as String?,
      animatedTypes.contains(type)
    else { return false }
    return CGImageSourceGetCount(source) > 1
  }

  func decode(_ data: Data) throws -> ImageContainer {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let first = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw ImageDecodingError.unknown
    }
    let count = CGImageSourceGetCount(source)
    // The size the frames are decoded at. ImageIO takes the bound as the
    // longer side of the result.
    let scale = bound?.scale(forWidth: first.width, height: first.height) ?? 1
    let longerSide = Int((CGFloat(max(first.width, first.height)) * scale).rounded(.up))
    let makeFrame: (Int) -> CGImage? = { index in
      guard scale < 1 else {
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, index, options)
      }
      let options =
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: longerSide,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
      return CGImageSourceCreateThumbnailAtIndex(source, index, options)
    }

    let frameBytes =
      Int((CGFloat(first.width) * scale).rounded(.up))
      * Int((CGFloat(first.height) * scale).rounded(.up)) * 4
    guard count > 1, frameBytes > 0, frameBytes * count <= Self.maxDecodedBytes else {
      // Too large to hold every frame: the first frame, like Nuke would.
      return ImageContainer(
        image: UIImage(cgImage: makeFrame(0) ?? first), type: Self.assetType(source))
    }

    var frames: [UIImage] = []
    var delays: [Int] = []  // centiseconds
    for index in 0..<count {
      guard let frame = makeFrame(index) else { continue }
      frames.append(UIImage(cgImage: frame))
      delays.append(Self.delayCentiseconds(source, index))
    }
    guard let image = Self.animatedImage(frames: frames, delays: delays) else {
      throw ImageDecodingError.unknown
    }
    return ImageContainer(image: image, type: Self.assetType(source), data: data)
  }

  /// `UIImage.animatedImage` plays frames at one uniform rate. Variable
  /// delays are kept by repeating each frame `delay / gcd` times (repeats
  /// share one bitmap, so they cost no pixel memory). Pathological timings
  /// that would need too many slots fall back to the average rate.
  private static func animatedImage(frames: [UIImage], delays: [Int]) -> UIImage? {
    guard !frames.isEmpty else { return nil }
    let total = delays.reduce(0, +)
    let unit = delays.reduce(0) { gcd($0, $1) }
    let slots = unit > 0 ? total / unit : Int.max
    let duration = Double(total) / 100
    guard slots <= maxExpandedFrames else {
      return UIImage.animatedImage(with: frames, duration: duration)
    }
    var expanded: [UIImage] = []
    expanded.reserveCapacity(slots)
    for (frame, delay) in zip(frames, delays) {
      expanded.append(contentsOf: repeatElement(frame, count: delay / unit))
    }
    return UIImage.animatedImage(with: expanded, duration: duration)
  }

  /// Browsers (and Android's decoder) treat delays of 10 ms or less as
  /// 100 ms: many GIFs declare 0 and rely on it.
  private static func delayCentiseconds(_ source: CGImageSource, _ index: Int) -> Int {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    let containers: [(CFString, CFString, CFString)] = [
      (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
      (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
      (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
    ]
    for (dictionaryKey, unclamped, clamped) in containers {
      guard let dictionary = properties?[dictionaryKey] as? [CFString: Any] else { continue }
      let seconds = (dictionary[unclamped] as? Double) ?? (dictionary[clamped] as? Double) ?? 0
      let centiseconds = Int((seconds * 100).rounded())
      return centiseconds <= 1 ? 10 : centiseconds
    }
    return 10
  }

  private static func assetType(_ source: CGImageSource) -> AssetType? {
    switch CGImageSourceGetType(source) as String? {
    case "com.compuserve.gif": .gif
    case "public.png": .png
    case "org.webmproject.webp": .webp
    default: nil
    }
  }

  private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
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
