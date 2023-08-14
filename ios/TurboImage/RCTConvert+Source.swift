import Foundation
import React
import Kingfisher

@objc
class Source: NSObject {
  var uri: String?
  
  init(uri: String) {
    self.uri = uri
  }
}


extension RCTConvert {
  @objc(Source:)
  static func source(_ json: [AnyHashable: Any]) -> Source? {
    guard let uri = json["uri"] as? String else { return nil }
    return Source(uri: uri)
  }
}

