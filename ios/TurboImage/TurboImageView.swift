import Kingfisher
import React

class TurboImageView : UIView {
  
  var image: UIImage?
  var imageView: UIImageView?
  private var needsReload: Bool = false
  
  var width: CGFloat? {
    didSet {
      guard let width = width else { return }
      imageView?.frame.size.width = width
    }
  }
  var height: CGFloat? {
    didSet {
      guard let height = height else { return }
      imageView?.frame.size.height = height
    }
  }
  
  @objc var source: Source? {
    didSet {
      needsReload = true
    }
  }
  
  var scaleMode: ScaleMode?
  
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
  
  @objc
  func setScaleMode(_ scaleMode: ScaleMode) {
    self.scaleMode = scaleMode
  }
  
  override func didSetProps(_ changedProps: [String]!) {
    if needsReload {
      loadImage(with: source)
    }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
}

extension TurboImageView {
  
  func loadImage(with source: Source?) {
    guard let source = source,
          let url = URL(string: source.uri!),
          let width = width,
          let height = height,
          let scaleMode = scaleMode
    else { return }
    
    let resource: KF.ImageResource = KF.ImageResource(downloadURL: url)
    let scale = UIScreen.main.scale
    let contentMode = ScaleMode.mapContentMode(by: scaleMode)
    let referenceSize = CGSize(width: width * scale, height: height * scale)
    let processor = ResizingImageProcessor(referenceSize: referenceSize,
                                           mode: contentMode)
    let options: KingfisherOptionsInfo = [.processor(processor)]
    imageView?.kf.indicatorType = .activity
    imageView?.kf.setImage(with: resource,
                           placeholder: nil,
                           options: options,
                           progressBlock: nil
    )
  }
}
