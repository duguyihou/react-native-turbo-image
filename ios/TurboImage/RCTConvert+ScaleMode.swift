import Foundation
import React
import Kingfisher

@objc
enum ScaleMode: Int {
  
  /// Not scale the content.
  case none
  
  /// Scales the content to fit the size of the view by maintaining the aspect ratio.
  case aspectFit
  
  /// Scales the content to fill the size of the view.
  case aspectFill
}

extension ScaleMode {
  
  static func mapContentMode(by scaleMode: ScaleMode) -> ContentMode {
    var contentMode: Kingfisher.ContentMode
    switch scaleMode.rawValue {
    case 1:
      contentMode = .aspectFit
    case 2:
      contentMode = .aspectFill
    default:
      contentMode = .none
    }
    return contentMode
  }
}


extension RCTConvert {
  @objc(ScaleMode:)
  static func scaleMode(_ value: Any) -> ScaleMode {
    let ScaleModeMap: [String: ScaleMode] = [
      "fill": .aspectFill,
      "fit": .aspectFit
    ]
    
    guard let value = value as? String,
          let mv = ScaleModeMap[value]
    else { return .none }
    return mv
  }
}

