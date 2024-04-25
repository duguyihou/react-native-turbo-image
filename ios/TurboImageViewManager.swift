import Nuke

@objc(TurboImageViewManager)
class TurboImageViewManager: RCTViewManager {

  override func view() -> (TurboImageView) {
    return TurboImageView()
  }

  @objc override static func requiresMainQueueSetup() -> Bool {
    return false
  }
}

extension TurboImageViewManager {

  @objc
  func prefetch(_ urlArray: [String],
                resolve: @escaping RCTPromiseResolveBlock,
                reject: @escaping RCTPromiseRejectBlock) {
    let prefetcher = ImagePrefetcher()
    let urls =  urlArray.map { url in URL(string: url )}.compactMap{ $0 }
    resolve(prefetcher.startPrefetching(with: urls))
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
