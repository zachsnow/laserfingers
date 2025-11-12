import Foundation
import SpriteKit

#if os(iOS) || os(tvOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

enum BackgroundImageResource {
    static let errorNotification = Notification.Name("BackgroundImageLoadFailed")
    
    private static let fileName = "bg"
    private static let fileExtension = "jpg"
    private static let directory = "Images"
    private static var cachedTexture: SKTexture?
    private static var didReportFailure = false
    
    static func texture() -> SKTexture? {
        if let cachedTexture {
            return cachedTexture
        }
        guard let image = loadImage() else {
            return nil
        }
        #if os(iOS) || os(tvOS)
        let texture = SKTexture(image: image)
        #else
        let texture = SKTexture(image: image)
        #endif
        cachedTexture = texture
        return texture
    }
    
    static func validatePresence() {
        _ = loadImage()
    }
    
    private static func loadImage() -> PlatformImage? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: directory) else {
            reportFailure("File \(directory)/\(fileName).\(fileExtension) is missing from the app bundle.")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            reportFailure("Unable to read data from \(directory)/\(fileName).\(fileExtension).")
            return nil
        }
        #if os(iOS) || os(tvOS)
        guard let image = PlatformImage(data: data) else {
            reportFailure("The image at \(directory)/\(fileName).\(fileExtension) is corrupted or has an unsupported format.")
            return nil
        }
        #else
        guard let image = PlatformImage(data: data) else {
            reportFailure("The image at \(directory)/\(fileName).\(fileExtension) is corrupted or has an unsupported format.")
            return nil
        }
        #endif
        print("loaded bg")

        return image
    }
    
    private static func reportFailure(_ details: String) {
        guard !didReportFailure else { return }
        didReportFailure = true
        let message = """
Background image load failure.

\(details)

Ensure \(directory)/\(fileName).\(fileExtension) is included in the Xcode project and copied into the app bundle.
"""
        NotificationCenter.default.post(name: errorNotification, object: nil, userInfo: ["message": message])
    }
}
