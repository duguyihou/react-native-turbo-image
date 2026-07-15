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

  @objc
  func prefetch(_ sources: [Source],
                with cachePolicy: String,
                resolve: @escaping RCTPromiseResolveBlock,
                reject: @escaping RCTPromiseRejectBlock) {

    let imageRequests = imageRequests(from: sources, includeResize: true)

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
  func clearMemoryCache(_ sources: [Source]?,
                        resolve: @escaping RCTPromiseResolveBlock,
                        reject: @escaping RCTPromiseRejectBlock) {
    guard let sources, !sources.isEmpty else {
      ImageCache.shared.removeAll()
      resolve("Success")
      return
    }
    for request in imageRequests(from: sources) {
      ImagePipeline.shared.cache.removeCachedImage(for: request, caches: [.memory])
    }
    resolve("Success")
  }

  @objc
  func clearDiskCache(_ sources: [Source]?,
                      resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) {
    guard let sources, !sources.isEmpty else {
      ImagePipeline(configuration: .withDataCache).cache.removeAll()
      DataLoader.sharedUrlCache.removeAllCachedResponses()
      resolve("Success")
      return
    }
    let dataCachePipeline = ImagePipeline(configuration: .withDataCache)
    for source in sources {
      guard let request = imageRequest(from: source) else { continue }
      dataCachePipeline.cache.removeCachedData(for: request)
      if let urlRequest = request.urlRequest {
        DataLoader.sharedUrlCache.removeCachedResponse(for: urlRequest)
      }
    }
    resolve("Success")
  }

  private func imageRequests(from sources: [Source], includeResize: Bool = false) -> [ImageRequest] {
    return sources.compactMap { imageRequest(from: $0, includeResize: includeResize) }
  }

  // `includeResize` must stay false for cache-clearing call sites: the resize
  // processor is baked into Nuke's cache key, so a clear request that isn't
  // built the exact same way as the original prefetch would silently miss the
  // cached entry. Clearing identifies entries by uri/cacheKey only.
  private func imageRequest(from source: Source, includeResize: Bool = false) -> ImageRequest? {
    guard let uri = source["uri"] as? String,
          let url = URL(string: uri)
    else { return nil }

    var urlRequest = URLRequest(url: url)
    if let headers = source["headers"] as? [String: String] {
      urlRequest.allHTTPHeaderFields = headers
    }

    var processors: [ImageProcessing] = []
    if includeResize, let resize = source["resize"] as? NSNumber {
      processors.append(ImageProcessors.Resize(width: resize.doubleValue))
    }

    var userInfo: [ImageRequest.UserInfoKey: Any] = [:]
    if let cacheKey = source["cacheKey"] as? String {
      userInfo[.imageIdKey] = cacheKey
    }
    return ImageRequest(urlRequest: urlRequest,
                        processors: processors,
                        userInfo: userInfo)
  }
}
