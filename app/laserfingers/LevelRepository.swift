import Foundation

enum LevelRepository {
    static func load() -> [Level] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        if let data = loadData(named: "levels", in: "Levels") ?? loadData(named: "levels", in: nil),
           let manifest = try? decoder.decode(LevelManifest.self, from: data) {
            return manifest.levels
        }
        return Level.fallback
    }
    
    private static func loadData(named name: String, in subdirectory: String?) -> Data? {
        let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: subdirectory)
            ?? Bundle.main.resourceURL?.appendingPathComponent(subdirectory.map { "\($0)/\(name).json" } ?? "\(name).json")
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }
}
