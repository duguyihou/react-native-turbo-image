import Kingfisher

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
  func clearAllCache() {
    ImageCache.default.clearCache()
  }
  
  @objc
  func clearMemoryCache() {
    ImageCache.default.clearMemoryCache()
  }
  
  @objc
  func clearDiskCache() {
    ImageCache.default.clearDiskCache()
  }
}


