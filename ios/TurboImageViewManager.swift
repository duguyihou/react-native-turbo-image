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
    let normal = sources.filter { !isPrefixFilter($0) }
    for request in imageRequests(from: normal) {
      ImagePipeline.shared.cache.removeCachedImage(for: request, caches: [.memory])
    }
    let filters = sources.filter { isPrefixFilter($0) }
    if !filters.isEmpty {
      for key in matchedKeys(from: filters) {
        ImagePipeline.shared.cache.removeCachedImage(for: cacheKeyRequest(for: key), caches: [.memory])
      }
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
      TurboImageCacheKeyIndex.shared.removeAll()
      resolve("Success")
      return
    }
    let dataCachePipeline = ImagePipeline(configuration: .withDataCache)
    let normal = sources.filter { !isPrefixFilter($0) }
    for source in normal {
      guard let request = imageRequest(from: source) else { continue }
      dataCachePipeline.cache.removeCachedData(for: request)
      if let urlRequest = request.urlRequest {
        DataLoader.sharedUrlCache.removeCachedResponse(for: urlRequest)
      }
    }
    let filters = sources.filter { isPrefixFilter($0) }
    if !filters.isEmpty {
      let keys = matchedKeys(from: filters)
      for key in keys {
        dataCachePipeline.cache.removeCachedData(for: cacheKeyRequest(for: key))
      }
      TurboImageCacheKeyIndex.shared.remove(keys)
    }
    resolve("Success")
  }

  // A prefix filter is `{ include_prefix?, exclude_prefix? }` with no `uri` -
  // distinguishes it from a normal Source dict passed to clear* calls.
  private func isPrefixFilter(_ source: Source) -> Bool {
    source["uri"] == nil && (source["include_prefix"] != nil || source["exclude_prefix"] != nil)
  }

  private func matchedKeys(from filters: [Source]) -> [String] {
    var result = Set<String>()
    for filter in filters {
      let include = filter["include_prefix"] as? String
      let exclude = filter["exclude_prefix"] as? String
      result.formUnion(TurboImageCacheKeyIndex.shared.keys(includePrefix: include, excludePrefix: exclude))
    }
    return Array(result)
  }

  // Nuke derives the cache key from `.imageIdKey` when present, ignoring the
  // URL - so a dummy URL is fine here, we only need it to target a known key.
  private func cacheKeyRequest(for key: String) -> ImageRequest {
    ImageRequest(url: URL(string: "about:blank")!, userInfo: [.imageIdKey: key])
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
    TurboImageCacheKeyIndex.shared.register((source["cacheKey"] as? String) ?? uri)
    return ImageRequest(urlRequest: urlRequest,
                        processors: processors,
                        userInfo: userInfo)
  }
}
