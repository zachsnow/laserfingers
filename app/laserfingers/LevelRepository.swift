import Foundation

enum LevelRepository {
    private static let downloadedDirectoryName = "99 Downloaded"
    private static let levelDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
    private static let metadataDecoder = JSONDecoder()
    
    struct DownloadedLevelInfo {
        let url: URL
        let metadata: DownloadedLevelMetadata
    }
    
    enum LoadingError: Swift.Error, CustomStringConvertible {
        case missingResourceDirectory(String)
        case unreadableResource(URL, Swift.Error)
        case decodeFailure(URL, Swift.Error)
        case storageUnavailable(Swift.Error)
        
        var description: String {
            switch self {
            case .missingResourceDirectory(let location):
                return "Levels directory not found: \(location)"
            case .unreadableResource(let url, let error):
                return "Unable to read resource at \(url.path): \(error)"
            case .decodeFailure(let url, let error):
                return "Unable to decode level at \(url.lastPathComponent): \(error)"
            case .storageUnavailable(let error):
                return "Unable to access user level storage: \(error)"
            }
        }
    }
    
    static func load() throws -> [LevelPack] {
        let device = DeviceProfile.current
        let bundlePacks = try loadPacks(
            in: try resolveBundleLevelsDirectory(),
            decoder: levelDecoder,
            device: device
        )
        let downloadedPack = try loadDownloadedPack(decoder: levelDecoder, device: device)
        return bundlePacks + [downloadedPack]
    }

    static func loadLevel(named resourceName: String, subdirectory: String = "Levels") throws -> Level {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) else {
            throw LoadingError.missingResourceDirectory("\(subdirectory)/\(resourceName).json")
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadingError.unreadableResource(url, error)
        }

        do {
            var level = try levelDecoder.decode(Level.self, from: data)
            level.setDirectory(url.deletingLastPathComponent())
            return level
        } catch let error as DecodingError {
            throw LoadingError.decodeFailure(url, error)
        } catch {
            throw LoadingError.unreadableResource(url, error)
        }
    }
    
    static func isDownloadedPack(_ pack: LevelPack) -> Bool {
        pack.directoryName == downloadedDirectoryName
    }
    
    static func downloadedLevelsDirectory() throws -> URL {
        let fileManager = FileManager.default
        do {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let levelsRoot = appSupport.appendingPathComponent("Levels", isDirectory: true)
            if !fileManager.directoryExists(at: levelsRoot) {
                try fileManager.createDirectory(at: levelsRoot, withIntermediateDirectories: true)
            }
            var downloaded = levelsRoot.appendingPathComponent(downloadedDirectoryName, isDirectory: true)
            if !fileManager.directoryExists(at: downloaded) {
                try fileManager.createDirectory(at: downloaded, withIntermediateDirectories: true)
            }
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try downloaded.setResourceValues(resourceValues)
            return downloaded
        } catch {
            throw LoadingError.storageUnavailable(error)
        }
    }
    
    private static func resolveBundleLevelsDirectory() throws -> URL {
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
    
    private static func loadPacks(in baseURL: URL, decoder: JSONDecoder, device: DeviceProfile.Kind) throws -> [LevelPack] {
        let packURLs = try directoryContents(at: baseURL)
        return try packURLs.compactMap { packURL in
            let levels = try loadLevels(in: packURL, decoder: decoder)
                .filter { $0.supports(device) }
            guard !levels.isEmpty else { return nil }
            return LevelPack(
                directoryName: packURL.lastPathComponent,
                name: packDisplayName(for: packURL.lastPathComponent),
                levels: levels
            )
        }
    }
    
    private static func loadDownloadedPack(decoder: JSONDecoder, device: DeviceProfile.Kind) throws -> LevelPack {
        let directory = try downloadedLevelsDirectory()
        let levels = try loadLevels(in: directory, decoder: decoder)
            .filter { $0.supports(device) }
        return LevelPack(
            directoryName: downloadedDirectoryName,
            name: packDisplayName(for: downloadedDirectoryName),
            levels: levels
        )
    }
    
    static func downloadedLevelMatch(for level: Level) throws -> DownloadedLevelInfo? {
        let entries = try enumerateDownloadedLevels()
        if let uuid = level.uuid,
           let match = entries.first(where: { $0.metadata.uuid == uuid }) {
            return match
        }
        return entries.first(where: { $0.metadata.id == level.id })
    }
    
    @discardableResult
    static func deleteDownloadedLevel(uuid: UUID?, id: String) throws -> Bool {
        let entries = try enumerateDownloadedLevels()
        let target = entries.first(where: {
            if let uuid, let candidate = $0.metadata.uuid {
                return candidate == uuid
            }
            return $0.metadata.id == id
        })
        guard let info = target else { return false }
        try FileManager.default.removeItem(at: info.url)
        return true
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
    
    private static func enumerateDownloadedLevels() throws -> [DownloadedLevelInfo] {
        let directory = try downloadedLevelsDirectory()
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else {
                #if DEBUG
                print("⚠️ Unable to read downloaded level file: \(url.lastPathComponent)")
                #endif
                return nil
            }
            guard let metadata = try? metadataDecoder.decode(DownloadedLevelMetadata.self, from: data) else {
                #if DEBUG
                print("⚠️ Unable to decode metadata for downloaded level: \(url.lastPathComponent)")
                #endif
                return nil
            }
            return DownloadedLevelInfo(url: url, metadata: metadata)
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

    static func saveLevel(_ level: Level, asNew: Bool) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directory = try downloadedLevelsDirectory()

        // Determine the ID to use
        let idToUse: String
        if asNew {
            // Generate a new ID with UUID suffix
            let uuid = UUID()
            // Remove any existing UUID suffix first
            let baseID = level.id.components(separatedBy: "-").dropLast().joined(separator: "-")
            idToUse = "\(baseID.isEmpty ? level.id : baseID)-\(uuid.uuidString.prefix(8))"
        } else {
            idToUse = level.id
        }

        let filename = "\(idToUse).json"
        let fileURL = directory.appendingPathComponent(filename)

        // Encode to JSON, then decode and modify the ID
        var data = try encoder.encode(level)
        if asNew {
            var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            json["id"] = idToUse
            data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        }

        try data.write(to: fileURL, options: .atomic)
        return idToUse
    }
}

private extension FileManager {
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

struct DownloadedLevelMetadata: Decodable {
    let id: String
    let uuid: UUID?
}
