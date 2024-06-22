import Foundation

public extension UIImage {
  func with(_ borderRadius: CGFloat? = nil) -> UIImage? {
    let maxRadius = min(size.width, size.height) / 2
    let cornerRadius: CGFloat
    if let radius = borderRadius, radius > 0 && radius <= maxRadius {
      cornerRadius = radius
    } else {
      cornerRadius = maxRadius
    }
    UIGraphicsBeginImageContextWithOptions(size, false, scale)
    let rect = CGRect(origin: .zero, size: size)
    UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
    draw(in: rect)
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image
  }
}
