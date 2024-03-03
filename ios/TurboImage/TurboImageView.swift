import Nuke
import NukeUI
import React

class TurboImageView : UIView {
  
  private lazy var lazyImageView = LazyImageView()
  @objc var onError: RCTDirectEventBlock?
  @objc var onSuccess: RCTDirectEventBlock?
  
  @objc var url: String? = nil {
    didSet {
      guard let url = url,
            let urlString = URL(string: url)
      else {
        onError?(["error": "invalid url: \(String(describing: url))"])
        return
      }
      lazyImageView.url = urlString
    }
  }
  
  @objc var resizeMode = "contain" {
    didSet {
      lazyImageView.contentMode = ResizeMode(rawValue: resizeMode)?.contentMode ?? .scaleAspectFit
    }
  }
  
  @objc var showActivityIndicator = false {
    didSet {
      lazyImageView.placeholderView = UIActivityIndicatorView()
    }
  }
  
  @objc var base64Placeholder: String? {
    didSet {
      DispatchQueue.global(qos: .userInteractive).async {
        DispatchQueue.main.async { [self] in
          self.lazyImageView.placeholderImage = UIImage(base64Placeholder: base64Placeholder)
        }
      }
    }
  }
  
  @objc var blurhash: String? {
    didSet {
      DispatchQueue.global(qos: .userInteractive).async {
        DispatchQueue.main.async { [self] in
          guard let image = UIImage(blurHash: blurhash ?? "",
                                    size: CGSize(width: 32, height: 32))
          else { return }
          self.lazyImageView.placeholderImage = image
        }
      }
    }
  }
  
  @objc var fadeDuration: NSNumber = 0.5 {
    didSet {
      lazyImageView.transition = .fadeIn(duration: fadeDuration.doubleValue)
    }
  }
  
  @objc var rounded: Bool = false {
    didSet {
      if rounded {
        lazyImageView.processors = [
          ImageProcessors.Circle()
        ]
      }
    }
  }
  
  @objc var cachePolicy = "memory" {
    didSet {
      lazyImageView.pipeline = CachePolicy(rawValue: cachePolicy)?.pipeline ?? .shared
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
    lazyImageView.onCompletion = { [weak self] result in
      self?.completionHandler(with: result)
    }
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

fileprivate extension TurboImageView {
  
  func completionHandler(with result: Result<ImageResponse, Error>) {
    switch result {
    case .success(let value):
      onSuccess?([
        "width": value.image.size.width,
        "height": value.image.size.height,
        "source": value.urlResponse?.url?.absoluteString ?? ""
      ])
    case .failure(let error):
      onError?([
        "error": error.localizedDescription,
      ])
    }
  }
}
