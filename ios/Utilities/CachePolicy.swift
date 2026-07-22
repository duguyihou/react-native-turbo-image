import Foundation
import Nuke

enum CachePolicy: String {
  case urlCache, dataCache

  static let dataCachePipeline = ImagePipeline(configuration: .withDataCache)

  var pipeline: ImagePipeline {
    switch self {
    case .urlCache:
      return .shared
    case .dataCache:
      return Self.dataCachePipeline
    }
  }
}
