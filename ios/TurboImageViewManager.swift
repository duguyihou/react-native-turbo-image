import Nuke

@objc(TurboImageViewManager)
class TurboImageViewManager: RCTViewManager {

  private var prefetchers: [String: ImagePrefetcher] = [:]

  override func view() -> (TurboImageView) {
    return TurboImageView()
  }

  @objc override static func requiresMainQueueSetup() -> Bool {
    return true
  }
}

extension TurboImageViewManager {

  typealias Source = [String: Any]

  private func parseRequestPriority(from priority: String?) -> ImageRequest.Priority {
    guard let priority = priority else { return .normal }
    switch priority {
    case "veryLow":
      return .veryLow
    case "low":
      return .low
    case "normal":
      return .normal
    case "high":
      return .high
    case "veryHigh":
      return .veryHigh
    default:
      return .normal
    }
  }

  @objc
  func prefetch(_ sources: [Source],
                with cachePolicy: String,
                resolve: @escaping RCTPromiseResolveBlock,
                reject: @escaping RCTPromiseRejectBlock) {
    
    let imageRequests: [ImageRequest] = sources.map {
      guard let uri = $0["uri"] as? String,
            let url = URL(string: uri)
      else { return nil }

      var urlRequest = URLRequest(url: url)
      if let headers = $0["headers"] as? [String: String] {
        urlRequest.allHTTPHeaderFields = headers
      }
      let priority = parseRequestPriority(from: $0["priority"] as? String)
      return ImageRequest(urlRequest: urlRequest, priority: priority)
    }.compactMap{ $0 }
    
    let key = UUID().uuidString
    var prefetcher: ImagePrefetcher?
    if(cachePolicy == "dataCache") {
      prefetcher = ImagePrefetcher(pipeline: ImagePipeline(configuration: .withDataCache))
    } else {
      prefetcher = ImagePrefetcher()
    }
    prefetchers[key] = prefetcher
    prefetcher?.startPrefetching(with: imageRequests)
    prefetcher?.didComplete = {
      resolve(true)
      self.prefetchers[key] = nil
    }
  }

  @objc
  func clearMemoryCache(_ resolve: @escaping RCTPromiseResolveBlock,
                        reject: @escaping RCTPromiseRejectBlock) {
    ImageCache.shared.removeAll()
    resolve("Success")
  }
  
  @objc
  func clearDiskCache(_ resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) {
    ImagePipeline(configuration: .withDataCache).cache.removeAll()
    DataLoader.sharedUrlCache.removeAllCachedResponses()
    resolve("Success")
  }
}
