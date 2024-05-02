import Nuke
import NukeUI
import SwiftSVG
import Gifu
import React

final class TurboImageView : UIView {

  private lazy var lazyImageView = LazyImageView()
  private var processors: [ImageProcessing] = []
  private var isSVG: Bool {
    return src?.hasSuffix(".svg") == true
  }
  private var isGif: Bool {
    return src?.hasSuffix(".gif") == true
  }
  @objc var onStart: RCTDirectEventBlock?
  @objc var onFailure: RCTDirectEventBlock?
  @objc var onSuccess: RCTDirectEventBlock?

  @objc var src: String? {
    didSet {
      guard let src,
            let _ = URL(string: src)
      else {
        onFailure?(["error": "invalid url: \(String(describing: src))"])
        return
      }
    }
  }

  @objc var rounded: Bool = false {
    didSet {
      if rounded {
        processors.append(ImageProcessors.Circle())
      }
    }
  }

  @objc var blur: NSNumber? {
    didSet {
      if let blur {
        processors.append(ImageProcessors
          .GaussianBlur(radius: blur.intValue))
      }
    }
  }

  @objc var borderRadius: NSNumber? {
    didSet {
      if let borderRadius {
        let radius = CGFloat(truncating: borderRadius)
        processors.append(ImageProcessors.RoundedCorners(radius: radius))
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
        processors.append(ImageProcessors
          .CoreImageFilter(name: name,
                           parameters: parameters,
                           identifier: identifier))
      }
    }
  }

  @objc var resize: NSArray? {
    didSet {
      if let resize = resize as? [NSNumber] {
        let width = CGFloat(truncating: resize[0])
        let height = CGFloat(truncating: resize[1])
       processors.append(ImageProcessors.Resize(size:
            .init(width: width, height: height)))
      }
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

  @objc var fadeDuration: NSNumber = 0.3 {
    didSet {
      lazyImageView.transition = .fadeIn(duration: 
                                          fadeDuration.doubleValue)
    }
  }

  @objc var cachePolicy = "memory" {
    didSet {
      let pipeline = CachePolicy(rawValue: cachePolicy)?.pipeline
      lazyImageView.pipeline = pipeline ?? .shared
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
    super.didSetProps(changedProps)
    defer { lazyImageView.url = URL(string: src!) }

    if isSVG {
      ImageDecoderRegistry.shared.register { context in
        context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
        ? ImageDecoders.Empty()
        : nil
      }
      lazyImageView.makeImageView = { container in
        if let data = container.data {
          let view = UIView(SVGData: data)
          self.addSubview(view)
          return view
        }
        return nil
      }
    }

    if isGif {
      lazyImageView.makeImageView = { container in
        if container.type == .gif,
           let data = container.data {
          let view = GIFImageView()
          view.animate(withGIFData: data)
          return view
        }
        return nil
      }
    }

    lazyImageView.onStart = { task in
      self.onStartHandler(with: task)
    }

    lazyImageView.onSuccess = { response in
      self.onSuccessHandler(with: response)
    }

    lazyImageView.onFailure = { error in
      self.onFailureHandler(with: error)
    }

    lazyImageView.processors = processors
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - callback handler
fileprivate extension TurboImageView {

  func onStartHandler(with task: ImageTask) {
    let payload = [
      "state": "running"
    ]
    onStart?(payload)
  }

  func onSuccessHandler(with response: ImageResponse) {
    let payload = [
      "width": response.image.size.width,
      "height": response.image.size.height,
      "source": response.request.url?.absoluteString ?? ""
    ] as [String : Any]

    onSuccess?(payload)
  }

  func onFailureHandler(with error: Error) {
    let payload = [
      "error": error.localizedDescription,
    ]

    onFailure?(payload)
  }
}
