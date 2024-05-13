import Nuke
import NukeUI
import SwiftSVG
import Gifu
import React

final class TurboImageView : UIView {

  private lazy var lazyImageView = LazyImageView()
  private var processors: [ImageProcessing] {
    return composeProcessors()
  }
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

  @objc var rounded: Bool = false

  @objc var blur: NSNumber?

  @objc var borderRadius: NSNumber?

  @objc var monochrome: UIColor!

  @objc var resize: NSArray?

  @objc var resizeMode = "contain" {
    didSet {
      let contentMode = ResizeMode(rawValue: resizeMode)?.contentMode
      lazyImageView.imageView.contentMode = contentMode ?? .scaleAspectFill
    }
  }

  @objc var indicator = "medium" {
    didSet {
      let indicatorView = indicator == "medium"
      ?  UIActivityIndicatorView(style: .medium)
      : UIActivityIndicatorView(style: .large)
      lazyImageView.placeholderView = indicatorView
    }
  }

  @objc var fadeDuration: NSNumber = 0.3 {
    didSet {
      lazyImageView.transition =
        .fadeIn(duration: fadeDuration.doubleValue)
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
      if let blurhash {
        DispatchQueue.global(qos: .userInteractive).async {
          let image = UIImage(blurHash: blurhash)
          DispatchQueue.main.async { [self] in
            lazyImageView.placeholderImage = image
          }
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

    defer {
      lazyImageView.url = URL(string: src!)
    }

    if isSVG {
      handleSvg()
    }

    if isGif {
      handleGif()
    }

    registerObservers()
    lazyImageView.processors = processors
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      lazyImageView.cancel()
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
// MARK: - other formats
fileprivate extension TurboImageView {

  func handleSvg() {
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

  func handleGif() {
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
}
// MARK: - processors
fileprivate extension TurboImageView {

  func composeProcessors() -> [ImageProcessing] {
    var initialProcessors: [ImageProcessing] = []

    if let resize = resize as? [NSNumber] {
      let width = CGFloat(truncating: resize[0])
      let height = CGFloat(truncating: resize[1])
      initialProcessors.append(ImageProcessors.Resize(size:
          .init(width: width, height: height)))
    }
    if let borderRadius {
      let radius = CGFloat(truncating: borderRadius)
      initialProcessors.append(ImageProcessors.RoundedCorners(radius: radius))
    }
    if rounded {
      initialProcessors.append(ImageProcessors.Circle())
    }
    if let blur {
      initialProcessors.append(ImageProcessors.GaussianBlur(radius: blur.intValue))
    }
    if let monochrome {
      let name = "CIColorMonochrome"
      let parameters = [
        "inputIntensity": 1,
        "inputColor": CIColor(color: monochrome)
      ] as [String : Any]
      let identifier = "turboImage.monochrome"
      initialProcessors.append(ImageProcessors
        .CoreImageFilter(name: name,
                         parameters: parameters,
                         identifier: identifier))
    }

    return initialProcessors
  }
}

// MARK: - callback handler
fileprivate extension TurboImageView {

  func registerObservers() {
    lazyImageView.onStart = { task in
      self.onStartHandler(with: task)
    }

    lazyImageView.onSuccess = { response in
      self.onSuccessHandler(with: response)
    }

    lazyImageView.onFailure = { error in
      self.onFailureHandler(with: error)
    }

  }

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
