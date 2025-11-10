import Foundation

enum LevelRepository {
    enum LoadingError: Swift.Error, CustomStringConvertible {
        case missingResource(String)
        case unreadableResource(URL, Swift.Error)
        case decodeFailure(Swift.Error)
        
        var description: String {
            switch self {
            case .missingResource(let location):
                return "levels.json not found in \(location)"
            case .unreadableResource(let url, let error):
                return "Unable to read levels.json at \(url.path): \(error)"
            case .decodeFailure(let error):
                return "Unable to decode levels.json: \(error)"
            }
        }
    }
    
    static func load() throws -> [Level] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let data = try loadData(named: "levels", preferredSubdirectory: "Levels")
        do {
            let manifest = try decoder.decode(LevelManifest.self, from: data)
            return manifest.levels
        } catch let error as DecodingError {
            throw LoadingError.decodeFailure(error)
        } catch {
            throw error
        }
    }
    
    private static func loadData(named name: String, preferredSubdirectory: String?) throws -> Data {
        let searchOrder: [String?] = [preferredSubdirectory, nil]
        for subdirectory in searchOrder {
            if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
                ?? Bundle.main.resourceURL?.appendingPathComponent(subdirectory.map { "\($0)/\(name).json" } ?? "\(name).json") {
                do {
                    return try Data(contentsOf: url)
                } catch {
                    throw LoadingError.unreadableResource(url, error)
                }
            }
        }
        throw LoadingError.missingResource(preferredSubdirectory ?? "main bundle root")
    }
}
