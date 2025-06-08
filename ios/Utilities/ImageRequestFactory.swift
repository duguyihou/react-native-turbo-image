import Photos
import Nuke

enum ImageRequestFactory {
  static func createImageRequest(from source: [String: Any]) -> ImageRequest? {
    guard let uri = source["uri"] as? String else { return nil }


    if uri.hasPrefix("ph://") {
      return createAssetImageRequest(uri: uri, source: source)
    } else if let url = URL(string: uri) {
      return createURLImageRequest(url: url, source: source)
    }

    return nil
  }

  private static func createAssetImageRequest(uri: String, source: [String: Any]) -> ImageRequest? {
    let assetId = String(uri.dropFirst("ph://".count))

    let size: CGSize?
    if let sizeDict = source["size"] as? [String: CGFloat],
       let width = sizeDict["width"],
       let height = sizeDict["height"] {
      size = CGSize(width: width, height: height)
    } else {
      size = nil
    }
    
    let cacheKey = source["cacheKey"] as? String
    
    var request = ImageRequest(
      id: cacheKey ?? assetId,
      data: { [] in
        if let size = size {
          return try await loadImageDataFromAsset(from: assetId, size: size)
        } else {
          return try await loadImageDataFromAsset(from: assetId)
        }
      }
    )
    
    if let cacheKey = cacheKey {
      request.userInfo[.imageIdKey] = cacheKey
    }
    
    return request
  }

  private static func createURLImageRequest(url: URL, source: [String: Any]) -> ImageRequest? {
    var urlRequest = URLRequest(url: url)

    if let headers = source["headers"] as? [String: String] {
      urlRequest.allHTTPHeaderFields = headers
    }

    if let cacheKey = source["cacheKey"] as? String {
      return ImageRequest(urlRequest: urlRequest, userInfo: [.imageIdKey: cacheKey])
    } else {
      return ImageRequest(urlRequest: urlRequest)
    }
  }


  private static func loadImageDataFromAsset(from assetId: String, size: CGSize? = nil) async throws -> Data {
    let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
    guard let asset = assets.firstObject else {
      throw NSError(domain: "TurboImageView", code: 404, userInfo: [NSLocalizedDescriptionKey: "Asset not found"])
    }

    return try await withCheckedThrowingContinuation { continuation in
      let options = PHImageRequestOptions()
      options.version = .current
      options.deliveryMode = .highQualityFormat
      options.isNetworkAccessAllowed = true

      if let size = size {
        // Request resized image
        PHImageManager.default().requestImage(
          for: asset,
          targetSize: size,
          contentMode: .aspectFit,
          options: options
        ) { (image, info) in
          if let error = info?[PHImageErrorKey] as? Error {
            continuation.resume(throwing: error)
          } else if let image = image,
                    let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.9) {
            continuation.resume(returning: imageData)
          } else {
            continuation.resume(throwing: NSError(
              domain: "TurboImageView",
              code: 500,
              userInfo: [NSLocalizedDescriptionKey: "Failed to load or convert image"]
            ))
          }
        }
      } else {
        // Request full image data
        PHImageManager.default().requestImageDataAndOrientation(
          for: asset,
          options: options
        ) { (imageData, dataUTI, orientation, info) in
          if let error = info?[PHImageErrorKey] as? Error {
            continuation.resume(throwing: error)
          } else if let imageData = imageData {
            continuation.resume(returning: imageData)
          } else {
            continuation.resume(throwing: NSError(
              domain: "TurboImageView",
              code: 500,
              userInfo: [NSLocalizedDescriptionKey: "Failed to load image data"]
            ))
          }
        }
      }
    }
  }
}
