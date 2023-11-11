import Kingfisher
import React

class TurboImageView : UIView {
  
  var imageView: UIImageView?
  var imageColor: UIColor?
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
  
  @objc var url: String? {
    didSet {
      needsReload = true
    }
  }
  
  var resizeMode: ResizeMode?
  
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
  func setResizeMode(_ resizeMode: ResizeMode) {
    self.resizeMode = resizeMode
  }
  
  @objc
  func setImageColor(_ imageColor: UIColor) {
    self.imageColor = imageColor
  }
  
  override func didSetProps(_ changedProps: [String]!) {
    if needsReload {
      loadImage(with: url)
    }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
}

extension TurboImageView {
  
  func loadImage(with url: String?) {
    guard let url = URL(string: url!),
          let width = width,
          let height = height
    else { return }
    
    let resource: KF.ImageResource = KF.ImageResource(downloadURL: url)
    var processor: ImageProcessor = DefaultImageProcessor.default
    if(resizeMode != nil) {
      let scale = UIScreen.main.scale
      let contentMode = ResizeMode.mapContentMode(by: resizeMode!)
      let referenceSize = CGSize(width: width * scale, height: height * scale)
      let resizingImageprocessor = ResizingImageProcessor(referenceSize: referenceSize,
                                                          mode: contentMode)
      processor = processor.append(another: resizingImageprocessor)
    }
    if (imageColor != nil) {
      let tintProcessor = TintImageProcessor(tint: imageColor!)
      processor = processor.append(another: tintProcessor)
    }
    
    let options: KingfisherOptionsInfo = [.processor(processor)]
    imageView?.kf.indicatorType = .activity
    imageView?.kf.setImage(with: resource,
                           placeholder: nil,
                           options: options,
                           progressBlock: nil
    )
  }
}
