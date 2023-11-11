import Kingfisher
import React

class TurboImageView : UIView {
  
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
  
  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(lazyImageView)
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
      .fade(duration: 1)
      .onSuccess({ result in
        self.onSuccess?(["result": result])
      })
      .onFailure({ error in
        self.onError?(["error": error.localizedDescription])
      })
      .set(to: lazyImageView)
  }
}
