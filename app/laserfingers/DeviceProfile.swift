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
            // Threshold distinguishes iPad Mini (≤2266 points) from larger iPads
            // iPad Mini 6: 2266 x 1488 native pixels
            // iPad Air/Pro: 2360+ x 1640+ native pixels
            let iPadMiniMaxNativePixels: CGFloat = 2300
            if maxNative <= iPadMiniMaxNativePixels {
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
