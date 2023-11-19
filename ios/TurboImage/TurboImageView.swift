import Kingfisher
import React

class TurboImageView : UIView {
  
  private var placeholder: UIImage?
  private var cornerRadius: CGFloat?
  lazy var lazyImageView = UIImageView()
  @objc var onError: RCTDirectEventBlock?
  @objc var onSuccess: RCTDirectEventBlock?
  
  @objc var url: String? = nil {
    didSet {
      guard url != nil else {
        onError?([
          "error": "Expected a valid url but got: \(url ?? "nil")",
        ])
        return
      }
    }
  }
  
  @objc var resizeMode = "contain" {
    didSet {
      lazyImageView.contentMode = ResizeMode(rawValue: resizeMode)?.contentMode ?? .scaleAspectFit
    }
  }
  
  @objc var showActivityIndicator = false {
    didSet {
      lazyImageView.kf.indicatorType = .activity
    }
  }
  
  @objc var base64Placeholder: String? {
    didSet {
      placeholder = UIImage(base64Placeholder: base64Placeholder)
    }
  }
  
  @objc var fadeDuration: NSNumber = 0.5
  
  @objc var rounded: Bool = false {
    didSet {
      guard let width = placeholder?.size.width else { return }
      cornerRadius = width
      placeholder = placeholder?.roundedCorner(with: width)
    }
  }
  
  @objc var tint: UIColor = .clear
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(lazyImageView)
    layer.masksToBounds = true
    lazyImageView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      lazyImageView.topAnchor.constraint(equalTo: topAnchor),
      lazyImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
      lazyImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      lazyImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }
  
  override func didSetProps(_ changedProps: [String]!) {
    loadImage()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

fileprivate extension TurboImageView {
  
  func loadImage() {
    guard let url = URL(string: url!)
    else { return }
    
    let processor = composeProcessor(tint, rounded)
    
    KF.url(url)
      .fade(duration: TimeInterval(truncating: fadeDuration))
      .placeholder(placeholder)
      .setProcessor(processor)
      .onSuccess({ result in
        self.onSuccess?(["result": "success"])
      })
      .onFailure({ error in
        self.onError?(["error": error.localizedDescription])
      })
      .set(to: lazyImageView)
  }
  
  func composeProcessor( _ tint: UIColor?, _ rounded: Bool?) -> ImageProcessor {
    var processor: ImageProcessor = DefaultImageProcessor.default
    
    if tint != nil && tint != .clear  {
      processor = processor |> TintImageProcessor(tint: tint!)
    }
    
    if rounded ?? false && (cornerRadius != nil) {
      processor = processor |> RoundCornerImageProcessor(cornerRadius: cornerRadius!)
    }
    
    return processor
  }
}
