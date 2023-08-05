import Kingfisher

class TurboImageView : UIView {
  
  var image: UIImage?
  @objc var color: String = "" {
    didSet {
      self.backgroundColor = hexStringToUIColor(hexColor: color)
    }
  }
  
  @objc var source: String?
  
  override init(frame: CGRect) {
    super.init(frame: frame)
  }
  
  override func didSetProps(_ changedProps: [String]!) {
    reloadImage()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
}
extension TurboImageView {
  
  private func reloadImage() {
    guard let url = URL(string: source!) else { return }
    let resource: KF.ImageResource = KF.ImageResource(downloadURL: url)
    KingfisherManager.shared.retrieveImage(with: resource) { [self] result in
      switch result {
      case .success(let response):
        image = response.image
        let imageView = UIImageView(image: image)
        addSubview(imageView)
      case .failure(let error):
        print("🐵 ---- error \(error)") // TODO: 🐵 handle error
      }
    }
  }
  
  func hexStringToUIColor(hexColor: String) -> UIColor {
    let stringScanner = Scanner(string: hexColor)
    
    if(hexColor.hasPrefix("#")) {
      stringScanner.scanLocation = 1
    }
    var color: UInt32 = 0
    stringScanner.scanHexInt32(&color)
    
    let r = CGFloat(Int(color >> 16) & 0x000000FF)
    let g = CGFloat(Int(color >> 8) & 0x000000FF)
    let b = CGFloat(Int(color) & 0x000000FF)
    
    return UIColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: 1)
  }
}
