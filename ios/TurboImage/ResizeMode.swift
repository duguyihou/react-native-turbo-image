import UIKit

/// Resize mode for the image.
/// - fill: Scale the image to fill the view.
/// - contain: Scale the image to fit the view.
/// - cover: Scale the image to fill the view, cropping if necessary.
/// - center: Center the image in the view.
enum ResizeMode: String {
    case fill, contain, cover, center
    
    var contentMode: UIView.ContentMode {
        switch self {
        case .fill: // TODO: 🐵 stretch?
            return .scaleToFill
        case .contain:
            return .scaleAspectFit
        case .cover:
            return .scaleAspectFill
        case .center:
            return .center
        }
    }
}
