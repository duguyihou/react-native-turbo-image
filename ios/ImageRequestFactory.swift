import Photos

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
        
        return ImageRequest(
            id: assetId,
            data: { [weak self] in
                if let size = size {
                    return try await self?.loadImageDataFromAsset(from: assetId, size: size) ?? Data()
                } else {
                    return try await self?.loadImageDataFromAsset(from: assetId) ?? Data()
                }
            }
        )
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
}
