import Nuke
import NukeUI
import SwiftSVG
import Gifu
import React

final class TurboImageView : UIView {
  
  private struct Constants {
    static let error = "error"
    static let state = "state"
    static let width = "width"
    static let height = "height"
    static let source = "source"
  }
  
  private lazy var lazyImageView = LazyImageView()
  private var processors: [ImageProcessing] {
    return composeProcessors()
  }
  
  @objc var onStart: RCTDirectEventBlock?
  @objc var onFailure: RCTDirectEventBlock?
  @objc var onSuccess: RCTDirectEventBlock?
  @objc var onCompletion: RCTDirectEventBlock?
  
  @objc var src: String? {
    didSet {
      guard let src,
            let _ = URL(string: src)
      else {
        onFailure?([
          Constants.error: "invalid url: \(String(describing: src))"
        ])
        return
      }
    }
  }
  
  @objc var rounded: Bool = false
  
  @objc var blur: NSNumber?
  
  @objc var borderRadius: NSNumber?
  
  @objc var monochrome: UIColor!
  
  @objc var resize: NSNumber?
  
  @objc var tint: UIColor!
  
  @objc var resizeMode = "contain" {
    didSet {
      let contentMode = ResizeMode(rawValue: resizeMode)?.contentMode
      lazyImageView.imageView.contentMode = contentMode ?? .scaleAspectFill
    }
  }
  
  @objc var indicator: NSDictionary? {
    didSet {
      guard let indicator else { return }
      let style = indicator.value(forKey: "style") as? String ?? "medium"
      let indicatorView = style == "large"
      ?  UIActivityIndicatorView(style: .large)
      : UIActivityIndicatorView(style: .medium)
      if let colorValue = indicator.value(forKey: "color") {
        indicatorView.color = RCTConvert.uiColor(colorValue)
      }
      lazyImageView.placeholderView = indicatorView
    }
  }
  
  @objc var placeholder: NSDictionary? {
    didSet {
      guard let placeholder else { return }
      
      if let blurhash = placeholder.value(forKey: "blurhash") as? String {
        DispatchQueue.global(qos: .userInteractive).async {
          let image = UIImage(blurHash: blurhash)
          DispatchQueue.main.async { [self] in
            lazyImageView.placeholderImage = image
          }
        }
      }
    }
  }
  
  @objc var fadeDuration: NSNumber = 300 {
    didSet {
      lazyImageView.transition =
        .fadeIn(duration: fadeDuration.doubleValue / 1000)
    }
  }
  
  @objc var cachePolicy = "memory" {
    didSet {
      let pipeline = CachePolicy(rawValue: cachePolicy)?.pipeline
      lazyImageView.pipeline = pipeline ?? .shared
    }
  }
  
  @objc var showPlaceholderOnFailure: Bool = false {
    didSet {
      if showPlaceholderOnFailure {
        lazyImageView.showPlaceholderOnFailure = showPlaceholderOnFailure
      }
    }
  }
  
  @objc var isSVG: Bool = false
  
  @objc var isGif: Bool = false
  
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
    
    if let resize {
      initialProcessors.append(
        ImageProcessors.Resize(width: resize.doubleValue))
    }
    if let borderRadius {
      let radius = CGFloat(truncating: borderRadius)
      initialProcessors.append(
        ImageProcessors.RoundedCorners(radius: radius))
    }
    if rounded {
      initialProcessors.append(
        ImageProcessors.Circle())
    }
    if let blur {
      initialProcessors.append(
        ImageProcessors.GaussianBlur(radius: blur.intValue))
    }
    if let monochrome {
      let name = "CIColorMonochrome"
      let parameters = [
        "inputIntensity": 1,
        "inputColor": CIColor(color: monochrome)
      ] as [String : Any]
      let identifier = "turboImage.monochrome"
      initialProcessors.append(
        ImageProcessors.CoreImageFilter(name: name,
                                        parameters: parameters,
                                        identifier: identifier))
    }
    
    if let tint {
      let tintProcessor = ImageProcessors
        .Anonymous(id: "turboImage.tint") { image in
          image.withTintColor(tint)
        }
      initialProcessors.append(tintProcessor)
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
    
    lazyImageView.onCompletion = { result in
      self.onCompletionHandler(with: result)
    }
    
  }
  
  func onStartHandler(with task: ImageTask) {
    let payload = [
      Constants.state: "running"
    ]
    onStart?(payload)
  }
  
  func onSuccessHandler(with response: ImageResponse) {
    let payload = [
      Constants.width: response.image.size.width,
      Constants.height: response.image.size.height,
      Constants.state: response.request.url?.absoluteString ?? ""
    ] as [String : Any]
    
    onSuccess?(payload)
  }
  
  func onFailureHandler(with error: Error) {
    let payload = [
      Constants.error: error.localizedDescription,
    ]
    
    onFailure?(payload)
  }
  
  func onCompletionHandler(with result: Result<ImageResponse, any Error>) {
    onCompletion?([Constants.state: "completed"])
  }
  
}
