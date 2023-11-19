import UIKit

public extension UIImage {
  
  convenience init?(base64Placeholder: String?) {
    guard
      let base64Placeholder,
      let data = Data(base64Encoded: base64Placeholder, options: .ignoreUnknownCharacters)
    else { return nil }
    self.init(data: data)
  }
  
  func roundedCorner(with radius: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { rendererContext in
      let rect = CGRect(origin: .zero, size: size)
      let path = UIBezierPath(roundedRect: rect,
                              byRoundingCorners: .allCorners,
                              cornerRadii: CGSize(width: radius, height: radius))
      path.close()
      
      let cgContext = rendererContext.cgContext
      cgContext.saveGState()
      path.addClip()
      draw(in: rect)
      cgContext.restoreGState()
    }
  }
}
