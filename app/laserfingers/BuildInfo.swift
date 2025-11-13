import Foundation

struct BuildInfo {
    let version: String
    let buildNumber: String
    let buildDate: Date?
    
    static func current(bundle: Bundle = .main) -> BuildInfo {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let buildDate = Self.bundleBuildDate(from: bundle)
        return BuildInfo(version: version, buildNumber: buildNumber, buildDate: buildDate)
    }
    
    var formattedBuildDate: String {
        guard let buildDate else { return "Unknown" }
        return BuildInfo.dateFormatter.string(from: buildDate)
    }
    
    private static func bundleBuildDate(from bundle: Bundle) -> Date? {
        guard let timestampString = bundle.object(forInfoDictionaryKey: "BuildTimestamp") as? String else {
            return nil
        }
        return iso8601Formatter.date(from: timestampString)
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
