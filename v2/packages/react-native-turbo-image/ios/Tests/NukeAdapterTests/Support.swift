// What every suite here needs: the real adapter, requests shaped like the
// ones the core resolves, and image files to load.
//
// The tests drive `NukeImageLoader` through the seam (`TIImageLoading`), as
// the Fabric view does, with files on disk in place of a server. So the
// decoder, the processor step and the memory cache are the ones an app runs.
// Each suite makes its own loader, and so its own memory cache.
//
// Not reachable this way: the key-addressed disk cache and the HTTP cache.
// Nuke does not store local files, and `urlCache` needs HTTP responses; both
// are covered on-device by the smoke suite and the fixture server.

import ImageIO
import NukeUI
import Testing
import TurboImageLoaderAPI
import UIKit
import UniformTypeIdentifiers

@testable import TurboImageNuke

/// What a completion delivered. `@unchecked Sendable` only to cross the
/// continuation: the seam completes on the main thread and every test runs
/// on the main actor, so it never leaves it.
struct Loaded: @unchecked Sendable {
  let image: UIImage?
  let animation: Any?
  let fromMemoryCache: Bool
  let error: NSError?

  /// The image's size in pixels, which is what `decodeSize` bounds.
  var pixelSize: CGSize? {
    image.map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
  }

  /// The failure as the seam's code, or nil for a success or for an error
  /// outside the seam's domain (which the seam forbids).
  var errorCode: TIImageLoadError.Code? {
    guard let error, error.domain == TIImageLoadErrorDomain else { return nil }
    return TIImageLoadError.Code(rawValue: error.code)
  }
}

@MainActor
struct Adapter {
  let loader = NukeImageLoader()

  func load(_ request: TIImageRequest) async -> Loaded {
    await loadTogether([request])[0]
  }

  /// Starts every load before waiting for any, and returns their results in
  /// the order of `requests`.
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

  func prefetch(_ request: TIImageRequest) async -> Bool {
    await withCheckedContinuation { continuation in
      _ = loader.prefetchRequest(request) { continuation.resume(returning: $0) }
    }
  }

  /// The loader's own image view, with a size: a view without one has
  /// nothing to decode frames for yet.
  func animatedView() throws -> AnimatedImageView {
    let view = try #require(loader.makeImageView() as? AnimatedImageView)
    view.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
    return view
  }

  /// A request as the core resolves one for a local file: memory tier only.
  /// `vectorSize` defaults to the decode bound, as it does for a view with
  /// `allowDownscaling` on.
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

/// Image files written for the test, so the suite carries none of its own.
enum Fixture {
  struct Failure: Error {}

  /// The size of every bitmap fixture, in pixels.
  static let size = CGSize(width: 40, height: 30)

  /// An animated GIF with an explicit loop count ("forever"), as nearly
  /// every GIF has.
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

/// A value a processor block, which runs on Nuke's processing queue, hands
/// back to the test.
final class Recorded<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Value?

  var value: Value? {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
