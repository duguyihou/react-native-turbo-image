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

  @objc
  func prefetch(_ sources: [String],
                resolve: @escaping RCTPromiseResolveBlock,
                reject: @escaping RCTPromiseRejectBlock) {
    let urls = sources.map { url in URL(string: url )}.compactMap{ $0 }
    prefetcher.startPrefetching(with: urls)
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
