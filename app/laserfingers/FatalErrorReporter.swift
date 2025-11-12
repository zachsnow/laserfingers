import Foundation

enum FatalErrorReporter {
    static let notification = Notification.Name("LaserfingersFatalErrorNotification")
    
    static func report(_ message: String) {
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: ["message": message]
        )
    }
}
