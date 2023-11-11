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
