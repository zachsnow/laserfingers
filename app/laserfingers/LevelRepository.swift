import Foundation

enum LevelRepository {
    enum LoadingError: Swift.Error, CustomStringConvertible {
        case missingResourceDirectory(String)
        case unreadableResource(URL, Swift.Error)
        case decodeFailure(URL, Swift.Error)
        
        var description: String {
            switch self {
            case .missingResourceDirectory(let location):
                return "Levels directory not found: \(location)"
            case .unreadableResource(let url, let error):
                return "Unable to read resource at \(url.path): \(error)"
            case .decodeFailure(let url, let error):
                return "Unable to decode level at \(url.lastPathComponent): \(error)"
            }
        }
    }
    
    static func load() throws -> [LevelPack] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let baseURL = try resolveLevelsDirectory()
        let packURLs = try directoryContents(at: baseURL)
        let device = DeviceProfile.current
        return try packURLs.compactMap { packURL in
            let levels = try loadLevels(in: packURL, decoder: decoder)
                .filter { $0.supports(device) }
            guard !levels.isEmpty else { return nil }
            let directoryName = packURL.lastPathComponent
            return LevelPack(
                directoryName: directoryName,
                name: packDisplayName(for: directoryName),
                levels: levels
            )
        }
    }
    
    private static func resolveLevelsDirectory() throws -> URL {
        let fileManager = FileManager.default
        if let root = Bundle.main.resourceURL {
            let levelsURL = root.appendingPathComponent("Levels", isDirectory: true)
            if fileManager.directoryExists(at: levelsURL) {
                return levelsURL
            }
        }
        if let bundleURL = Bundle.main.url(forResource: "Levels", withExtension: nil),
           fileManager.directoryExists(at: bundleURL) {
            return bundleURL
        }
        let bundlePath = Bundle.main.resourceURL?.path ?? Bundle.main.bundlePath
        throw LoadingError.missingResourceDirectory("\(bundlePath)/Levels")
    }
    
    private static func directoryContents(at url: URL) throws -> [URL] {
        let fileManager = FileManager.default
        do {
            return try fileManager
                .contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .filter { fileManager.directoryExists(at: $0) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw LoadingError.unreadableResource(url, error)
        }
    }
    
    private static func loadLevels(in directory: URL, decoder: JSONDecoder) throws -> [Level] {
        let fileManager = FileManager.default
        let levelFiles: [URL]
        do {
            levelFiles = try fileManager
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw LoadingError.unreadableResource(directory, error)
        }
        
        return try levelFiles.map { url in
            do {
                let data = try Data(contentsOf: url)
                var level = try decoder.decode(Level.self, from: data)
                level.setDirectory(url.deletingLastPathComponent())
                return level
            } catch let error as DecodingError {
                throw LoadingError.decodeFailure(url, error)
            } catch {
                throw LoadingError.unreadableResource(url, error)
            }
        }
    }
    
    private static func packDisplayName(for directoryName: String) -> String {
        let trimmed = directoryName.trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\s*"#, options: []) else {
            return trimmed
        }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        let displayName = regex.stringByReplacingMatches(in: trimmed, options: [], range: range, withTemplate: "")
        let finalName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return finalName.isEmpty ? trimmed : finalName
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
