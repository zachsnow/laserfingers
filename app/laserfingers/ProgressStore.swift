import Foundation

struct GameSettings: Codable {
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var advancedModeEnabled: Bool = false
    var infiniteSlotsEnabled: Bool = false
    var glowEnabled: Bool = true
    var blurEnabled: Bool = true
    var afterimageEnabled: Bool = true
    
    init() {}
    
    private enum CodingKeys: String, CodingKey {
        case soundEnabled
        case hapticsEnabled
        case advancedModeEnabled
        case infiniteSlotsEnabled
        case glowEnabled
        case blurEnabled
        case afterimageEnabled
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        advancedModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .advancedModeEnabled) ?? false
        infiniteSlotsEnabled = try container.decodeIfPresent(Bool.self, forKey: .infiniteSlotsEnabled) ?? false
        glowEnabled = try container.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? true
        blurEnabled = try container.decodeIfPresent(Bool.self, forKey: .blurEnabled) ?? true
        afterimageEnabled = try container.decodeIfPresent(Bool.self, forKey: .afterimageEnabled) ?? true
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(hapticsEnabled, forKey: .hapticsEnabled)
        try container.encode(advancedModeEnabled, forKey: .advancedModeEnabled)
        try container.encode(infiniteSlotsEnabled, forKey: .infiniteSlotsEnabled)
        try container.encode(glowEnabled, forKey: .glowEnabled)
        try container.encode(blurEnabled, forKey: .blurEnabled)
        try container.encode(afterimageEnabled, forKey: .afterimageEnabled)
    }
}

final class ProgressStore {
    private enum Keys {
        static let progress = "laserfingers.levelProgress"
        static let settings = "laserfingers.gameSettings"
    }
    
    private struct StoredLevelProgress: Codable {
        let levelId: String
        let uuid: String?
        let state: LevelProgress.State
        
        private enum CodingKeys: String, CodingKey {
            case levelId
            case uuid
            case state
        }
        
        init(levelId: String, uuid: String?, state: LevelProgress.State) {
            self.levelId = levelId
            self.uuid = uuid
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
            uuid = try? container.decodeIfPresent(String.self, forKey: .uuid)
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
        let stateMap = Dictionary(stored.map { (($0.uuid ?? $0.levelId), $0.state) }) { current, _ in current }
        return levels.enumerated().map { index, level in
            let fallbackState: LevelProgress.State = index == 0 ? .unlocked : .locked
            let key = level.uuid?.uuidString ?? level.id
            let state = stateMap[key] ?? fallbackState
            return LevelProgress(level: level, state: state)
        }
    }
    
    func saveProgress(_ entries: [LevelProgress]) {
        let stored = entries.map {
            StoredLevelProgress(
                levelId: $0.level.id,
                uuid: $0.level.uuid?.uuidString,
                state: $0.state
            )
        }
        guard let data = try? encoder.encode(stored) else { return }
        defaults.set(data, forKey: Keys.progress)
    }
}
