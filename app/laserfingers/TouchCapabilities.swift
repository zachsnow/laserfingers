import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum TouchCapabilities {
    static var maxSimultaneousTouches: Int {
        #if os(iOS)
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return 10
        case .mac:
            return 10
        default:
            return 5
        }
        #elseif os(macOS)
        return 10
        #else
        return 5
        #endif
    }
}
