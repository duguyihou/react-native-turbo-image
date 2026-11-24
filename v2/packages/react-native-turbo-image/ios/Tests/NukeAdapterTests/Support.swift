// Shared helpers: drive the real `NukeImageLoader` through the seam with local
// files. Each suite has its own loader and memory cache. Disk and HTTP caches
// need a server, so the smoke suite covers them.

import ImageIO
import NukeUI
import Testing
import TurboImageLoaderAPI
import UIKit
import UniformTypeIdentifiers

@testable import TurboImageNuke

/// A completion's result. `@unchecked Sendable` only to cross the
/// continuation; it never leaves the main thread.
struct Loaded: @unchecked Sendable {
  let image: UIImage?
  let animation: Any?
  let fromMemoryCache: Bool
  let error: NSError?

  /// Size in pixels.
  var pixelSize: CGSize? {
    image.map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
  }

  /// The seam error code, or nil.
  var errorCode: TIImageLoadError.Code? {
    guard let error, error.domain == TIImageLoadErrorDomain else { return nil }
    return TIImageLoadError.Code(rawValue: error.code)
  }
}

@MainActor
struct Adapter {
  let loader: NukeImageLoader

  init(loader: NukeImageLoader = NukeImageLoader()) {
    self.loader = loader
  }

  func load(_ request: TIImageRequest) async -> Loaded {
    await loadTogether([request])[0]
  }

  /// Starts all loads, then returns results in order.
  func loadTogether(_ requests: [TIImageRequest]) async -> [Loaded] {
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

  /// `imageSizeForRequest:`, as the cache module calls it.
  func size(_ request: TIImageRequest) async -> (size: CGSize, error: NSError?) {
    await withCheckedContinuation { continuation in
      _ = loader.imageSize(for: request) { size, error in
        continuation.resume(returning: (size, error as NSError?))
      }
    }
  }

  func prefetch(_ request: TIImageRequest) async -> Bool {
    await withCheckedContinuation { continuation in
      _ = loader.prefetchRequest(request) { continuation.resume(returning: $0) }
    }
  }

  /// The loader's image view, sized so it decodes frames.
  func animatedView() throws -> AnimatedImageView {
    let view = try #require(loader.makeImageView() as? AnimatedImageView)
    view.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
    return view
  }

  /// A local-file request (memory tier only). `vectorSize` defaults to `decodeSize`.
  func request(
    for file: URL,
    cacheKey: String = UUID().uuidString,
    decodeSize: CGSize = .zero,
    decodeFill: Bool = false,
    vectorSize: CGSize? = nil,
    displayScale: CGFloat = 1,
    memoryCacheRead: Bool = true,
    memoryCacheWrite: Bool = true,
    allowNetwork: Bool = true,
    processorKey: String = "",
    processor: TIImageProcessor? = nil
  ) -> TIImageRequest {
    TIImageRequest(
      url: file, cacheKey: cacheKey,
      memoryCacheRead: memoryCacheRead, memoryCacheWrite: memoryCacheWrite,
      diskCacheRead: false, diskCacheWrite: false, allowNetwork: allowNetwork,
      processorKey: processorKey, processor: processor, headers: [], httpCache: false,
      decode: decodeSize, decodeFill: decodeFill,
      vectorDecode: vectorSize ?? decodeSize, vectorDecodeFill: decodeFill, displayScale: displayScale)
  }
}

/// Image files generated at test time.
enum Fixture {
  struct Failure: Error {}

  /// Bitmap fixture size in pixels.
  static let size = CGSize(width: 40, height: 30)

  /// An animated GIF that loops forever.
  static func gif(frames: Int = 3) throws -> URL {
    let url = temporaryFile("gif")
    let destination = try unwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil))
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

  /// A 40×30 JPEG with EXIF orientation 6, so it displays as 30×40.
  static func rotatedJpeg() throws -> URL {
    let url = temporaryFile("jpg")
    let destination = try unwrap(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(
      destination, try unwrap(picture(shade: 0.3).cgImage),
      [kCGImagePropertyOrientation: 6] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw Failure() }
    return url
  }

  /// A 120×80 SVG, the smoke suite's logo.
  static func svg() throws -> URL {
    let url = temporaryFile("svg")
    let text = """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
        <rect width="120" height="80" fill="#182038"/>
        <circle cx="40" cy="40" r="24" fill="#e63946"/>
      </svg>
      """
    try Data(text.utf8).write(to: url)
    return url
  }

  /// Bytes no decoder recognises, under an image's name.
  static func notAnImage() throws -> URL {
    let url = temporaryFile("png")
    try Data("this is not an image".utf8).write(to: url)
    return url
  }

  /// A file URL with nothing behind it.
  static func missing() -> URL {
    temporaryFile("png")
  }

  private static func picture(shade: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor(white: shade, alpha: 1).setFill()
      context.fill(CGRect(origin: .zero, size: size))
      UIColor.red.setFill()
      context.fill(CGRect(x: size.width * shade, y: 10, width: 6, height: 6))
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

/// Passes a value from a processor block (off main) back to the test.
final class Recorded<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value?

  var value: Value? {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
