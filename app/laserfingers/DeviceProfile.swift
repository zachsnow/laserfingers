import UIKit

enum DeviceProfile {
    enum Kind: String {
        case iPhone = "iPhone"
        case iPadMini = "iPad Mini"
        case iPad = "iPad"
    }
    
    static let current: Kind = {
        #if targetEnvironment(macCatalyst)
        return .iPad
        #else
        let idiom = UIDevice.current.userInterfaceIdiom
        switch idiom {
        case .pad:
            let maxNative = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
            if maxNative <= 2300 {
                return .iPadMini
            } else {
                return .iPad
            }
        default:
            return .iPhone
        }
        #endif
    }()
}
