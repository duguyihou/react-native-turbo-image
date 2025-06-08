import Nuke
import NukeUI

@objc(TurboImageViewManager)
class TurboImageViewManager: RCTViewManager {

  private var prefetcher: ImagePrefetcher?

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
    let imageRequests = sources.compactMap { source -> ImageRequest? in
      guard let sourceDict = source as? [String: Any] else {
        return nil
      }
      return ImageRequestFactory.createImageRequest(from: sourceDict)
    }
    if(cachePolicy == "dataCache") {
      prefetcher = ImagePrefetcher(pipeline: ImagePipeline(configuration: .withDataCache))
    } else {
      prefetcher = ImagePrefetcher()
    }
    prefetcher?.startPrefetching(with: imageRequests)
    prefetcher?.didComplete = {
      resolve(true)
    }
  }

  @objc
  func dispose(_ sources: [Source],
               resolve: @escaping RCTPromiseResolveBlock,
               reject: @escaping RCTPromiseRejectBlock) {
    let imageRequests = sources.compactMap { source -> ImageRequest? in
      guard let sourceDict = source as? [String: Any] else {
        return nil
      }
      return ImageRequestFactory.createImageRequest(from: sourceDict)
    }

    prefetcher?.stopPrefetching(with: imageRequests)
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
