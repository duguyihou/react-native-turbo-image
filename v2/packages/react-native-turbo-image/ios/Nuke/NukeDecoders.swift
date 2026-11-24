// Decoders picked by content:
//   * animated GIF/APNG/WebP: Nuke's still plus an attached animation,
//   * SVG: private CoreSVG (App Review risk accepted, see migration-plan.md),
//   * everything else: Nuke's default.

import Foundation
import ImageIO
import Nuke
import UIKit

enum TurboImageDecoders {
  /// `makeImageDecoder`. Nuke picks a task's decoder from the first chunk and
  /// keeps it, so return a dispatcher that decides on the complete bytes.
  static func make(_ context: ImageDecodingContext, animations: AnimationSources) -> (any ImageDecoding)? {
    ContentDecoder(
      fallback: ImageDecoders.Default(context: context),
      // The adapter sets `imageID` to the request's cache key.
      cacheKey: context.request.imageID,
      animations: animations)
  }
}

/// Picks a decoder by content on complete data; partial previews use Nuke's.
struct ContentDecoder: ImageDecoding {
  /// Nuke's decoder, if it recognised the data (holds preview state and `thumbnail`).
  let fallback: ImageDecoders.Default?
  let cacheKey: String?
  let animations: AnimationSources

  func decode(_ data: Data) throws -> ImageContainer {
    if SVGDecoder.isSVG(data) {
      return try SVGDecoder().decode(data)
    }
    // The still (first frame if animated), within the decode bound.
    var container = try (fallback ?? ImageDecoders.Default()).decode(data)
    if let animation = animations.source(in: data, cacheKey: cacheKey) {
      container.animation = animation
      // So the memory cache counts the animation's bytes.
      container.data = animation.data
    }
    return container
  }

  func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
    fallback?.decodePartiallyDownloadedData(data)
  }
}

/// Skips Nuke's decompression for SVG, which would rasterise the vector.
final class TurboImagePipelineDelegate: ImagePipeline.Delegate {
  func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
    guard pipeline.configuration.isDecompressionEnabled else { return false }
    return response.container.type != SVGDecoder.assetType
  }
}

// MARK: - Animated images

/// Finds the animation in a complete image. Replaces Nuke's parsing, which
/// skips `thumbnail` requests and also animates HEIC/AVIF (stills on Android).
/// Hands out one source per image, so all view sizes share frames.
final class AnimationSources: @unchecked Sendable {
  // Only the documented animated formats (TIFF/ICO/HEIC can be multi-image too).
  private static let animatedTypes: Set<String> = [
    "com.compuserve.gif", "public.png", "org.webmproject.webp",
  ]

  // Weak, so evicted images' bytes are freed. Locked: decodes run concurrently.
  private let lock = NSLock()
  private let live = NSMapTable<NSString, AnimatedImageSource>.strongToWeakObjects()

  /// Nil for a still, including a single-frame GIF and a plain PNG.
  func source(in data: Data, cacheKey: String?) -> AnimatedImageSource? {
    // Cheap header check first; `AnimatedImageSource` reads every frame delay.
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
    // Parsed outside the lock (slow). Delays <= 10 ms become 100 ms, as browsers do.
    guard let source = AnimatedImageSource(data: data) else { return nil }
    return lock.withLock {
      // Re-check: two sizes may decode at once; the second takes the first's.
      if let existing = live.object(forKey: key), existing.data == data {
        return existing
      }
      live.setObject(source, forKey: key)
      return source
    }
  }

  /// Compares bytes too: a key's image can change (dispose, revalidation).
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

  /// Cheap sniff for an `<svg` element near the start.
  static func isSVG(_ data: Data) -> Bool {
    // Lossy: the cut may split a UTF-8 character.
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

/// Rasterises a vector image for a processor (`vectorDecodeSize`).
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
    // At its own size, keep the point size; fitted to a view, 1x like Nuke's bitmaps.
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
    // Cap at 4096 px (Coil's `maxBitmapSize`), or fill could ask for a huge bitmap.
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

/// CoreSVG via dlsym plus private `+[UIImage _imageWithCGSVGDocument:]`.
/// Every symbol is checked, so a removed one fails as `decode`, not a crash.
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
