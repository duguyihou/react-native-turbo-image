import Nuke
import NukeUI
import React

final class TurboImageView : UIView {

  private lazy var lazyImageView = LazyImageView()
  @objc var onError: RCTDirectEventBlock?
  @objc var onSuccess: RCTDirectEventBlock?
  private var processors: [ImageProcessing] = []

  @objc var url: String? {
    didSet {
      guard let url,
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
      let contentMode = ResizeMode(rawValue: resizeMode)?.contentMode
      lazyImageView.contentMode = contentMode ?? .scaleAspectFit
    }
  }

  @objc var showActivityIndicator = false {
    didSet {
      lazyImageView.placeholderView = UIActivityIndicatorView()
    }
  }

  @objc var blurhash: String? {
    didSet {
      DispatchQueue.global(qos: .userInteractive).async {
        DispatchQueue.main.async { [self] in
          guard let image = UIImage(blurHash: blurhash) else { return }
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
        processors.append(ImageProcessors.Circle())
        lazyImageView.processors = processors
      }
    }
  }

  @objc var blur: NSNumber? {
    didSet {
      if let blur {
        processors.append(ImageProcessors.GaussianBlur(radius: blur.intValue))
        lazyImageView.processors = processors
      }
    }
  }

  @objc var cachePolicy = "memory" {
    didSet {
      let pipeline = CachePolicy(rawValue: cachePolicy)?.pipeline
      lazyImageView.pipeline = pipeline ?? .shared
    }
  }
  
  @objc var borderRadius: NSNumber? {
    didSet {
      if let borderRadius {
        let radius = CGFloat(truncating: borderRadius)
        processors.append(ImageProcessors.RoundedCorners(radius: radius))
        lazyImageView.processors = processors
      }
    }
  }

  @objc var monochrome: UIColor! {
    didSet {
      if let monochrome {
        let name = "CIColorMonochrome"
        let parameters = [
          "inputIntensity": 1,
          "inputColor": CIColor(color: monochrome)
        ] as [String : Any]
        let identifier = "turboImage.monochrome"
        processors.append(ImageProcessors.CoreImageFilter(name: name,
                                                           parameters: parameters,
                                                           identifier: identifier))
        lazyImageView.processors = processors
      }
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
