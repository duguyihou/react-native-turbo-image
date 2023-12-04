import Kingfisher
import React

class TurboImageView : UIView {
  
  private var placeholder: UIImage?
  private var cornerRadius: CGFloat = 0.0
  private var enableCacheMemoryOnly: Bool = false
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
  
  @objc var blurhash: String? {
    didSet {
      placeholder = UIImage(blurHash: blurhash ?? "",
                            size: CGSize(width: 32, height: 32))
    }
  }
  
  @objc var fadeDuration: NSNumber = 0.5
  
  @objc var rounded: Bool = false {
    didSet {
      cornerRadius = 0.5
      if let width = placeholder?.size.width {
        placeholder = placeholder?.roundedCorner(with: width)
      }
    }
  }
  
  @objc var tint: UIColor = .clear
  
  @objc var cachePolicy = "shared" {
    didSet {
      enableCacheMemoryOnly = cachePolicy == CachePolicy.memory.rawValue
    }
  }
  
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
    
    KF.url(url)
      .fade(duration: TimeInterval(truncating: fadeDuration))
      .placeholder(placeholder)
      .tint(color: tint)
      .roundCorner(radius:.widthFraction(cornerRadius))
      .cacheMemoryOnly(enableCacheMemoryOnly)
      .onSuccess({ result in
        self.onSuccess?(["result": "success"])
      })
      .onFailure({ error in
        self.onError?(["error": error.localizedDescription])
      })
      .set(to: lazyImageView)
  }
}
