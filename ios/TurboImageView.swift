import Nuke
import NukeUI
#if !os(tvOS) && canImport(VisionKit)
import VisionKit
#endif
import Gifu
import React
import APNGKit

@MainActor
final class TurboImageView : UIView {
  
  private struct Constants {
    static let error = "error"
    static let state = "state"
    static let completed = "completed"
    static let total = "total"
    static let width = "width"
    static let height = "height"
    static let source = "source"
    static let svg = "svg"
    static let gif = "gif"
    static let apng = "apng"
  }
  
  private lazy var lazyImageView = LazyImageView()
  private var processors: [ImageProcessing] {
    return composeProcessors()
  }
  
  private var imageRequest: ImageRequest?
  private var requestInFlight: Bool = false
  #if !os(tvOS) && canImport(VisionKit)
  private var liveTextTask: Task<Void, Never>?
  #endif
  
  @objc var onStart: RCTDirectEventBlock?
  @objc var onProgress: RCTDirectEventBlock?
  @objc var onFailure: RCTDirectEventBlock?
  @objc var onSuccess: RCTDirectEventBlock?
  @objc var onCompletion: RCTDirectEventBlock?
  
  @objc var source: NSDictionary? {
    didSet {
      guard let uri = source?.value(forKey: "uri") as? String,
            let url = URL(string: uri) else {
        onFailure?([
          Constants.error: "invalid source: \(String(describing: source))"
        ])
        return
      }
      var urlRequest = URLRequest(url: url)
      if let headers = source?.value(forKey: "headers") as? [String:String] {
        urlRequest.allHTTPHeaderFields = headers
      }
      if let cacheKey = source?.value(forKey: "cacheKey") as? String {
        imageRequest = ImageRequest(urlRequest: urlRequest, userInfo: [.imageIdKey: cacheKey])
      } else {
        imageRequest = ImageRequest(urlRequest: urlRequest)
      }
    }
  }
  
  @objc var rounded: Bool = false
  
  @objc var blur: NSNumber?
  
  @objc var monochrome: UIColor!
  
  @objc var resize: NSNumber?
  
  @objc var tint: UIColor!
  
  @objc var resizeMode = "contain" {
    didSet {
      let contentMode = ResizeMode(rawValue: resizeMode)?.contentMode
      lazyImageView.imageView.contentMode = contentMode ?? .scaleAspectFill
      lazyImageView.placeholderView?.contentMode = contentMode ?? .scaleAspectFill
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
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
          let image = UIImage(blurHash: blurhash)
          DispatchQueue.main.async { [weak self] in
            self?.lazyImageView.placeholderImage = image
          }
        }
      }
      
      if let thumbhash = placeholder.value(forKey: "thumbhash") as? String {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
          let image = UIImage(thumbhash: thumbhash)
          DispatchQueue.main.async { [weak self] in
            self?.lazyImageView.placeholderImage = image
          }
        }
      }
      
      if let memoryCacheKey = placeholder.value(forKey: "memoryCacheKey") as? String {
        let request = ImageRequest(url: URL(string: memoryCacheKey))
        let memoryCachedImage = ImagePipeline.shared.cache.cachedImage(for: request, caches: .memory)?.image
        lazyImageView.placeholderImage = memoryCachedImage
      }
    }
  }
  
  @objc var fadeDuration: NSNumber = 300
  
  @objc var cachePolicy = "urlCache" {
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
  
  @objc var enableLiveTextInteraction: Bool = false
  
  @objc var isProgressiveImageRenderingEnabled: Bool = true {
    didSet {
      lazyImageView.isProgressiveImageRenderingEnabled = isProgressiveImageRenderingEnabled
    }
  }
  
  @objc var format: NSString? {
    didSet {
      guard let format = format as? String else { return }
      if format == Constants.svg {
        handleSvg()
      }
      if format == Constants.gif {
        handleGif()
      }
      if format == Constants.apng {
        handleAPNG()
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
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(cancelRequest),
                                           name: UIScene.didEnterBackgroundNotification,
                                           object: nil)
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(reloadRequest),
                                           name: UIScene.willEnterForegroundNotification,
                                           object: nil)
  }
  
  override func didSetProps(_ changedProps: [String]!) {
    super.didSetProps(changedProps)
    
    let duration = fadeDuration.doubleValue / 1000
    if duration > 0 && placeholder != nil {
      lazyImageView.transition = .custom { view, _ in
        view.imageView.alpha = 0
        view.placeholderView?.isHidden = false
        UIView.animate(withDuration: duration, animations: {
          view.imageView.alpha = 1
        }, completion: { _ in
          view.placeholderView?.isHidden = true
        })
      }
    } else {
      lazyImageView.transition = .fadeIn(duration: duration)
    }
    lazyImageView.processors = processors
    
    if !Set(["source", "resize", "blur","monochrome", "tint"])
      .intersection(changedProps).isEmpty {
      reloadImage()
    }
  }
  
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      #if !os(tvOS) && canImport(VisionKit)
      liveTextTask?.cancel()
      liveTextTask = nil
      #endif
    }
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

fileprivate extension TurboImageView {
  func reloadImage() {
    registerObservers()
    if let imageRequest {
      lazyImageView.request = imageRequest
    }
  }
  
  @objc func cancelRequest() {
    if requestInFlight {
      lazyImageView.cancel()
    }
  }
  
  @objc func reloadRequest() {
    if requestInFlight {
      lazyImageView.reset()
      reloadImage()
    }
  }
}

// MARK: - other formats
fileprivate extension TurboImageView {
  
  func handleSvg() {
    struct Static {
      static var didRegister = false
    }
    if !Static.didRegister {
      ImageDecoderRegistry.shared.register { context in
        let svgTagEnd = "</svg>"
        if let _ = context.data.range(of: Data(svgTagEnd.utf8), options: .backwards) {
          return ImageDecoders.Empty()
        } else {
          return nil
        }
      }
      Static.didRegister = true
    }
    
    lazyImageView.makeImageView = { container in
      if let data = container.data,
         let svg = SVG(data) {
        let image = svg.image()
        let view = UIImageView(image: image)
        return view
      }
      return nil
    }
  }
  
  func handleGif() {
    lazyImageView.makeImageView = { [weak self] container in
      guard let self else { return nil }
      if container.type == .gif,
         let data = container.data {
        let view = GIFImageView()
        view.contentMode = ResizeMode(rawValue: self.resizeMode)?.contentMode ?? .scaleToFill
        view.animate(withGIFData: data)
        return view
      }
      return nil
    }
  }
  
  func handleAPNG() {
    struct Static {
      static var didRegister = false
    }
    if !Static.didRegister {
      ImageDecoderRegistry.shared.register { context in
        // Signature bytes for the acTL chunk in an APNG file
        let acTLSignature = Data([0x61, 0x63, 0x54, 0x4C])
        // Search for the acTL chunk signature in the data
        if let _ = context.data.range(of: acTLSignature) {
          return ImageDecoders.Empty()
        } else {
          return nil
        }
      }
      Static.didRegister = true
    }
    
    lazyImageView.makeImageView = { container in
      guard let data = container.data else { return nil }
      let view = APNGImageView(frame: .zero)
      let image = try? APNGImage(data: data, decodingOptions: .fullFirstPass)
      view.image = image
      return view
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
      let identifier = "turboImage.monochrome.\(monochrome)"
      initialProcessors.append(
        ImageProcessors.CoreImageFilter(name: name,
                                        parameters: parameters,
                                        identifier: identifier))
    }
    
    if let tint {
      let tintProcessor = ImageProcessors
        .Anonymous(id: "turboImage.tint.\(tint)") { image in
          image.withTintColor(tint)
        }
      initialProcessors.append(tintProcessor)
    }
    
    return initialProcessors
  }
}

// MARK: - events
fileprivate extension TurboImageView {
  
  func registerObservers() {
    lazyImageView.onStart = { [weak self] task in
      guard let self else { return }
      self.requestInFlight = true
      self.onStartHandler(with: task)
    }
    
    lazyImageView.onProgress = { [weak self] progress in
      guard let self else { return }
      self.onProgressHandler(with: progress)
    }
    
    lazyImageView.onSuccess = { [weak self] response in
      guard let self else { return }
      self.requestInFlight = false
      self.onSuccessHandler(with: response)
    }
    
    lazyImageView.onFailure = { [weak self] error in
      guard let self else { return }
      self.requestInFlight = false
      self.onFailureHandler(with: error)
    }
    
    lazyImageView.onCompletion = { [weak self] result in
      guard let self else { return }
      self.requestInFlight = false
      self.onCompletionHandler(with: result)
#if !os(tvOS) && canImport(VisionKit)
      if self.enableLiveTextInteraction {
        self.handleLiveTextInteraction()
      }
#endif
    }
    
  }
  
  func onStartHandler(with task: ImageTask) {
    let payload = [
      Constants.state: "running"
    ]
    onStart?(payload)
  }
  
  func onProgressHandler(with progress: ImageTask.Progress) {
    let payload = [
      Constants.completed: progress.completed,
      Constants.total: progress.total
    ]
    
    onProgress?(payload)
  }
  
  func onSuccessHandler(with response: ImageResponse) {
    let payload = [
      Constants.width: response.image.size.width,
      Constants.height: response.image.size.height,
      Constants.source: response.request.url?.absoluteString ?? ""
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

// MARK: - live text
fileprivate extension TurboImageView {
  func handleLiveTextInteraction() {
    guard #available(iOS 16.0, *), ImageAnalyzer.isSupported, let image = lazyImageView.imageView.image else { return }
    
    let interaction = ImageAnalysisInteraction()
    lazyImageView.imageView.addInteraction(interaction)
    #if !os(tvOS)
    liveTextTask?.cancel()
    liveTextTask = Task { [weak self] in
      guard let self else { return }
      let analyzer = ImageAnalyzer()
      let configuration = ImageAnalyzer.Configuration([
        .text,.machineReadableCode,.visualLookUp
      ])
      let analysis = try? await analyzer.analyze(image, configuration: configuration)
      if let analysis {
        // Ensure imageView is still alive
        await MainActor.run { [weak self] in
          guard let self else { return }
          interaction.analysis = analysis
          interaction.preferredInteractionTypes = .automatic
        }
      }
    }
    #endif
  }
}
