
@objc(TurboImageViewManager)
class TurboImageViewManager: RCTViewManager {
  
  override func view() -> (TurboImageView) {
    return TurboImageView()
  }
  
  @objc override static func requiresMainQueueSetup() -> Bool {
    return false
  }
}

//extension TurboImageViewManager {
//  
//  @objc
//  func prefetch(_ urlArray: [String],
//                resolve: @escaping RCTPromiseResolveBlock,
//                reject: @escaping RCTPromiseRejectBlock) {
//    let urls =  urlArray.map { url in URL(string: url )}.compactMap{ $0 }
//    let prefetcher = ImagePrefetcher(urls: urls)
//    resolve(prefetcher.start())
//  }
//  
//  @objc
//  func clearAllCache(_ resolve: @escaping RCTPromiseResolveBlock,
//                     reject: @escaping RCTPromiseRejectBlock) {
//    resolve(ImageCache.default.clearCache())
//  }
//  
//  @objc
//  func clearMemoryCache(_ resolve: @escaping RCTPromiseResolveBlock,
//                        reject: @escaping RCTPromiseRejectBlock) {
//    resolve(ImageCache.default.clearMemoryCache())
//  }
//  
//  @objc
//  func clearDiskCache(_ resolve: @escaping RCTPromiseResolveBlock,
//                      reject: @escaping RCTPromiseRejectBlock) {
//    resolve(ImageCache.default.clearDiskCache())
//  }
//}
