import Kingfisher
import React

class TurboImageView : UIView {
  
  var image: UIImage?
  var imageView: UIImageView?
  
  var width: CGFloat?
  var height: CGFloat?
  
  @objc var source: String?
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    imageView = UIImageView()
    addSubview(imageView!)
  }
  
  @objc
  func setHeight(_ height: CGFloat) {
    self.height = height
  }
  
  @objc
  func setWidth(_ width: CGFloat) {
    self.width = width
  }
  
  override func didSetProps(_ changedProps: [String]!) {
    
    guard let width = width,
          let height = height,
          let source = source else { return }
    imageView?.frame.size.width = width
    imageView?.frame.size.height = height
    guard let url = URL(string: source) else { return }
    let resource: KF.ImageResource = KF.ImageResource(downloadURL: url)
    
    let processor = ResizingImageProcessor(referenceSize: .init(width: 300, height: 300), mode: .aspectFill)
    let options: KingfisherOptionsInfo = [.processor(DefaultImageProcessor.default)]
    imageView?.kf.indicatorType = .activity
    imageView?.kf.setImage(with: resource,
                           placeholder: nil,
                           options: options,
                           progressBlock: nil
    )
    
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
}

extension UIImageView {
  
  func resizeImage(image: UIImage, newWidth: CGFloat) -> UIImage {
    
    let scale = newWidth / image.size.width
    let newHeight = image.size.height * scale
    UIGraphicsBeginImageContext(CGSize(width: newWidth, height: newHeight))
    image.draw(in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
    let newImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return newImage!
  }
}
