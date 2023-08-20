import Foundation
import React
import Kingfisher

@objc
enum ResizeMode: Int {
  
  /// Not scale the content.
  case none
  
  /// Scales the content to fit the size of the view by maintaining the aspect ratio.
  case aspectFit
  
  /// Scales the content to fill the size of the view.
  case aspectFill
}

extension ResizeMode {
  
  static func mapContentMode(by resizeMode: ResizeMode) -> Kingfisher.ContentMode {
    var contentMode: Kingfisher.ContentMode
    switch resizeMode.rawValue {
    case 1:
      contentMode = .aspectFill
    case 2:
      contentMode = .aspectFit
    default:
      contentMode = .none
    }
    return contentMode
  }
}


extension RCTConvert {
  @objc(ResizeMode:)
  static func resizeMode(_ value: Any) -> ResizeMode {
    let ResizeModeMap: [String: ResizeMode] = [
      "fill": .aspectFill,
      "fit": .aspectFit
    ]
    
    guard let value = value as? String,
          let mv = ResizeModeMap[value]
    else { return .none }
    return mv
  }
}

