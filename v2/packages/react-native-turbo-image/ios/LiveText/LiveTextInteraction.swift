// Swift side of `TILiveTextInteraction` (TILiveText.h): VisionKit has no ObjC API.
// One interaction per view; stale analyses are dropped.

// Empty on tvOS (no VisionKit), so Live Text is a no-op there.
#if os(iOS)

import UIKit
import VisionKit

// SwiftPM: the seam is a separate Clang target. CocoaPods: same module.
#if canImport(TurboImageLoaderAPI)
  import TurboImageLoaderAPI
#endif

@objc(TurboImageLiveTextInteraction)
@MainActor
public final class LiveTextInteraction: NSObject, TILiveTextInteraction {
  // Apple recommends reusing one analyzer; it is safe to share.
  private static let analyzer = ImageAnalyzer()
  // Text, codes, and Visual Look Up (iOS 17+). Built per analysis because
  // `Configuration` is not Sendable; a fresh value can be sent.
  nonisolated private static func makeConfiguration() -> ImageAnalyzer.Configuration {
    var types: ImageAnalyzer.AnalysisTypes = [.text, .machineReadableCode]
    if #available(iOS 17.0, *) {
      types.insert(.visualLookUp)
    }
    return ImageAnalyzer.Configuration(types)
  }

  private let interaction = ImageAnalysisInteraction()
  private weak var imageView: UIImageView?
  private var analysisTask: Task<Void, Never>?

  @objc public static func makeIfSupported() -> (any TILiveTextInteraction)? {
    ImageAnalyzer.isSupported ? LiveTextInteraction() : nil
  }

  @objc(analyzeImage:inImageView:)
  public func analyze(_ image: UIImage, in imageView: UIImageView) {
    if self.imageView !== imageView {
      self.imageView?.removeInteraction(interaction)
      imageView.addInteraction(interaction)
      self.imageView = imageView
    }
    // UIImageView ignores touches by default; the interaction needs them.
    imageView.isUserInteractionEnabled = true
    interaction.analysis = nil

    analysisTask?.cancel()
    analysisTask = Task { [weak self] in
      let configuration = Self.makeConfiguration()
      let analysis = try? await Self.analyzer.analyze(image, configuration: configuration)
      // Cancelled means a newer image (or detach) superseded this one.
      guard let self, !Task.isCancelled, let analysis else { return }
      self.interaction.analysis = analysis
      self.interaction.preferredInteractionTypes = .automatic
    }
  }

  @objc public func detach() {
    analysisTask?.cancel()
    analysisTask = nil
    interaction.analysis = nil
    imageView?.removeInteraction(interaction)
    imageView?.isUserInteractionEnabled = false
    imageView = nil
  }
}

#endif  // os(iOS)
