import Nuke

@objc(TurboImageViewManager)
class TurboImageViewManager: RCTViewManager {

  private let prefetcher = ImagePrefetcher()

  override func view() -> (TurboImageView) {
    return TurboImageView()
  }

  @objc override static func requiresMainQueueSetup() -> Bool {
    return true
  }
}

extension TurboImageViewManager {

  typealias Source = [String: Any]

  @objc
  func prefetch(_ sources: [Source],
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
      return ImageRequest(urlRequest: urlRequest)
    }.compactMap{ $0 }

    prefetcher.startPrefetching(with: imageRequests)
    resolve("Success")
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
