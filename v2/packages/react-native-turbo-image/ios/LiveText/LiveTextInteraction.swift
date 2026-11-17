// Live Text for TurboImage (iOS 16+), the Swift side of `TILiveTextInteraction`.
//
// Only this target imports VisionKit's image-analysis API, which has no
// Objective-C surface. The Fabric view reaches it through the ObjC protocol
// in ios/LoaderAPI/include/TILiveText.h.
//
// Differences from 1.x, which added a new `ImageAnalysisInteraction` on
// every load completion: one interaction per view, attached once; an
// analysis for an image that has since been replaced is dropped; and turning
// the prop off removes the interaction instead of waiting for the next load.

import UIKit
import VisionKit

// SwiftPM: the seam is a separate Clang target. CocoaPods: same module.
#if canImport(TurboImageLoaderAPI)
  import TurboImageLoaderAPI
#endif

@available(iOS 16.0, *)
@objc(TurboImageLiveTextInteraction)
@MainActor
public final class LiveTextInteraction: NSObject, TILiveTextInteraction {
  // Apple recommends reusing one analyzer; it is safe to share.
  private static let analyzer = ImageAnalyzer()
  // 1.x's analysis types: text, QR/barcodes, and Visual Look Up subjects.
  // Visual Look Up needs iOS 17; on 16 the other two still work. Built per
  // analysis: `Configuration` is not Sendable, so a shared instance cannot
  // be handed to the (nonisolated) analyzer under Swift 6. A fresh value
  // from a nonisolated function is disconnected, so it can be sent.
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
