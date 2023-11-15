import UIKit

public extension UIImage {
    
    convenience init?(base64Placeholder: String?) {
        guard
            let base64Placeholder,
            let data = Data(base64Encoded: base64Placeholder, options: .ignoreUnknownCharacters)
        else { return nil }
        self.init(data: data)
    }
}
