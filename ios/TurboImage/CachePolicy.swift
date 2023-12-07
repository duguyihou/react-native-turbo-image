import Foundation
import Nuke

enum CachePolicy: String {
  case memory, urlCache, dataCache
  
  var pipeline: ImagePipeline {
      switch self {
      case .memory:
          return .shared
      case .urlCache:
          return ImagePipeline(configuration: .withURLCache)
      case .dataCache:
          return ImagePipeline(configuration: .withDataCache)
      }
  }
}
