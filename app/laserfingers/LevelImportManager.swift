import Foundation

struct LevelImportManager {
    struct PreparedImport {
        let level: Level
        let encodedData: Data
        let existingFileURL: URL?
        fileprivate let slug: String
    }
    
    enum ImportError: LocalizedError {
        case emptyPayload
        case payloadTooLarge(limit: Int)
        case invalidBase64
        case invalidJSON(String)
        
        var errorDescription: String? {
            switch self {
            case .emptyPayload:
                return "Paste a level JSON or Base64 string to continue."
            case .payloadTooLarge(let limit):
                return "Level data is too large (limit \(limit / 1024) KB)."
            case .invalidBase64:
                return "The provided text is not valid Base64 or JSON."
            case .invalidJSON(let message):
                return "Unable to decode level JSON: \(message)"
            }
        }
    }
    
    private let maxPayloadBytes = 64 * 1024
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    
    func prepareImport(from input: String) throws -> PreparedImport {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyPayload }
        let rawData = try decodePayload(trimmed)
        guard rawData.count <= maxPayloadBytes else {
            throw ImportError.payloadTooLarge(limit: maxPayloadBytes)
        }
        do {
            var level = try decoder.decode(Level.self, from: rawData)
            level.setDirectory(try LevelRepository.downloadedLevelsDirectory())
            let encoded = try encoder.encode(level)
            let existing = try existingFileURL(for: level.id)
            return PreparedImport(
                level: level,
                encodedData: encoded,
                existingFileURL: existing,
                slug: slug(for: level)
            )
        } catch let decodeError as DecodingError {
            throw ImportError.invalidJSON(decodingErrorDescription(decodeError))
        } catch let repoError as LevelRepository.LoadingError {
            throw repoError
        } catch {
            throw ImportError.invalidJSON(error.localizedDescription)
        }
    }
    
    func persist(_ prepared: PreparedImport, overwrite: Bool) throws -> URL {
        let directory = try LevelRepository.downloadedLevelsDirectory()
        let targetURL: URL
        if overwrite, let existing = prepared.existingFileURL {
            targetURL = existing
        } else {
            let sequence = (try highestSequenceNumber(in: directory) ?? 0) + 1
            let filename = String(format: "%02d-%@.json", sequence, prepared.slug)
            targetURL = directory.appendingPathComponent(filename, isDirectory: false)
        }
        try prepared.encodedData.write(to: targetURL, options: [.atomic])
        return targetURL
    }
    
    // MARK: - Helpers
    
    private func decodePayload(_ input: String) throws -> Data {
        if input.first == "{" {
            return Data(input.utf8)
        }
        let normalized = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let decoded = Data(base64Encoded: normalized) ?? Data(base64Encoded: normalized + padding(for: normalized)) else {
            throw ImportError.invalidBase64
        }
        return decoded
    }
    
    private func padding(for input: String) -> String {
        let remainder = input.count % 4
        guard remainder != 0 else { return "" }
        return String(repeating: "=", count: 4 - remainder)
    }
    
    private func existingFileURL(for levelID: String) throws -> URL? {
        guard !levelID.isEmpty else { return nil }
        let directory = try LevelRepository.downloadedLevelsDirectory()
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let metadata = try? decoder.decode(LevelIDProbe.self, from: data)
            else { continue }
            if metadata.id == levelID {
                return file
            }
        }
        return nil
    }
    
    private func highestSequenceNumber(in directory: URL) throws -> Int? {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let numbers = files.compactMap { url -> Int? in
            let name = url.deletingPathExtension().lastPathComponent
            let digits = name.prefix { $0.isNumber }
            return Int(digits)
        }
        return numbers.max()
    }
    
    private func slug(for level: Level) -> String {
        let base: String
        if !level.id.isEmpty {
            base = level.id
        } else if !level.title.isEmpty {
            base = level.title
        } else {
            base = "custom-level"
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedScalars = base.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        var slug = String(sanitizedScalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        slug = slug.replacingOccurrences(of: "--", with: "-")
        if slug.isEmpty { slug = "custom-level" }
        if slug.count > 32 {
            slug = String(slug.prefix(32))
        }
        return slug
    }
    
    private func decodingErrorDescription(_ error: DecodingError) -> String {
        func pathString(from codingPath: [CodingKey]) -> String {
            codingPath
                .map { key -> String in
                    if let index = key.intValue {
                        return "[\(index)]"
                    }
                    return key.stringValue
                }
                .joined(separator: ".")
        }
        
        let summary: String
        switch error {
        case .dataCorrupted(let context):
            summary = context.debugDescription
        case .keyNotFound(let key, _):
            summary = "Missing key '\(key.stringValue)'"
        case .typeMismatch(_, let context):
            summary = context.debugDescription
        case .valueNotFound(_, let context):
            summary = context.debugDescription
        @unknown default:
            summary = error.localizedDescription
        }
        if let context = errorContext(from: error),
           !context.codingPath.isEmpty {
            return summary + " at " + pathString(from: context.codingPath)
        }
        return summary
    }
    
    private func errorContext(from error: DecodingError) -> DecodingError.Context? {
        switch error {
        case .dataCorrupted(let context),
             .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .keyNotFound(_, let context):
            return context
        @unknown default:
            return nil
        }
    }
}

private struct LevelIDProbe: Decodable {
    let id: String
}
