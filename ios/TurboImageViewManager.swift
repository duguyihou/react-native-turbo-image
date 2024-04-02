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
    resolve(ImageCache.shared.removeAll())
  }

  @objc
  func clearDiskCache(_ resolve: @escaping RCTPromiseResolveBlock,
                      reject: @escaping RCTPromiseRejectBlock) {
    resolve(DataLoader.sharedUrlCache.removeAllCachedResponses())
  }
}
