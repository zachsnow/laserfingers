import Foundation

struct GameSettings: Codable {
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var advancedModeEnabled: Bool = false
    var infiniteSlotsEnabled: Bool = false
}

final class ProgressStore {
    private enum Keys {
        static let progress = "laserfingers.levelProgress"
        static let settings = "laserfingers.gameSettings"
    }
    
    private struct StoredLevelProgress: Codable {
        let levelId: String
        let state: LevelProgress.State
        
        private enum CodingKeys: String, CodingKey {
            case levelId
            case state
        }
        
        init(levelId: String, state: LevelProgress.State) {
            self.levelId = levelId
            self.state = state
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let stringId = try? container.decode(String.self, forKey: .levelId) {
                levelId = stringId
            } else if let intId = try? container.decode(Int.self, forKey: .levelId) {
                levelId = String(intId)
            } else {
                levelId = ""
            }
            state = (try? container.decode(LevelProgress.State.self, forKey: .state)) ?? .locked
        }
    }
    
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    func loadSettings() -> GameSettings {
        guard
            let data = defaults.data(forKey: Keys.settings),
            let settings = try? decoder.decode(GameSettings.self, from: data)
        else {
            return GameSettings()
        }
        return settings
    }
    
    func saveSettings(_ settings: GameSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Keys.settings)
    }
    
    func loadProgress(for levels: [Level]) -> [LevelProgress] {
        let defaultProgress = levels.enumerated().map { index, level in
            LevelProgress(level: level, state: index == 0 ? .unlocked : .locked)
        }
        guard
            let data = defaults.data(forKey: Keys.progress),
            let stored = try? decoder.decode([StoredLevelProgress].self, from: data)
        else {
            return defaultProgress
        }
        let stateMap = Dictionary(uniqueKeysWithValues: stored.map { ($0.levelId, $0.state) })
        return levels.enumerated().map { index, level in
            let fallbackState: LevelProgress.State = index == 0 ? .unlocked : .locked
            let state = stateMap[level.id] ?? fallbackState
            return LevelProgress(level: level, state: state)
        }
    }
    
    func saveProgress(_ entries: [LevelProgress]) {
        let stored = entries.map { StoredLevelProgress(levelId: $0.level.id, state: $0.state) }
        guard let data = try? encoder.encode(stored) else { return }
        defaults.set(data, forKey: Keys.progress)
    }
}
