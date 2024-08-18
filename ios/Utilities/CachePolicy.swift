import Foundation
import Nuke

enum CachePolicy: String {
  case urlCache, dataCache

  var pipeline: ImagePipeline {
    switch self {
    case .urlCache:
      return .shared
    case .dataCache:
      return ImagePipeline(configuration: .withDataCache)
    }
  }
}
