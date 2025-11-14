//
//  LaserfingersApp.swift
//  laserfingers
//
//  Created by Zach Snow on 11/9/25.
//

import SwiftUI
import Combine
import SpriteKit

@main
struct LaserfingersApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    coordinator.handleIncomingURL(url)
                }
        }
        .defaultAppStorage(UserDefaults.standard)
    }
}

// MARK: - Coordinator & Models
 
final class AppCoordinator: ObservableObject {
    enum Screen {
        case mainMenu
        case settings
        case about
        case levelSelect
        case gameplay
        case advancedMenu
        case levelEditor
    }
    @Published var screen: Screen = .mainMenu
    @Published var settings: GameSettings {
        didSet { progressStore.saveSettings(settings) }
    }
    @Published private(set) var levelProgress: [LevelProgress] = []
    @Published var activeGame: GameRuntime?
    @Published var loadErrorMessage: String?
    @Published var importSheetState: ImportSheetState?
    @Published var levelEditorViewModel: LevelEditorViewModel?
    
    private let progressStore = ProgressStore()
    private var levelPacks: [LevelPack] = []
    private var levels: [Level] = []
    private var cancellables: Set<AnyCancellable> = []
    private var screenBeforeLevelEditor: Screen?
    
    init() {
        let storedSettings = progressStore.loadSettings()
        _settings = Published(initialValue: storedSettings)
        
        do {
            try reloadLevelsInternal(unlocking: nil)
        } catch {
            loadErrorMessage = String(describing: error)
            levelPacks = []
            levels = []
            levelProgress = []
        }
        
        NotificationCenter.default.publisher(for: FatalErrorReporter.notification)
            .compactMap { $0.userInfo?["message"] as? String }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.loadErrorMessage = message
            }
            .store(in: &cancellables)
    }
    
    func goToMainMenu() {
        screen = .mainMenu
    }
    
    func showSettings() {
        screen = .settings
    }
    
    func showAbout() {
        screen = .about
    }
    
    func showAdvancedMenu() {
        guard settings.advancedModeEnabled else { return }
        screen = .advancedMenu
    }
    
    func openLevelEditor(with level: Level?) {
        guard settings.advancedModeEnabled else { return }
        screenBeforeLevelEditor = screen
        levelEditorViewModel = LevelEditorViewModel(level: level, settings: settings)
        screen = .levelEditor
    }
    
    func exitLevelEditor() {
        levelEditorViewModel = nil
        let destination = screenBeforeLevelEditor ?? .mainMenu
        screenBeforeLevelEditor = nil
        screen = destination
    }
    
    func showLevelSelect() {
        guard loadErrorMessage == nil else { return }
        screen = .levelSelect
    }
    
    func startLevel(_ level: Level) {
        guard loadErrorMessage == nil else { return }
        guard let progressIndex = indexOfLevel(level, in: levelProgress) else { return }
        guard levelProgress[progressIndex].state != .locked else { return }
        if levelProgress[progressIndex].state == .unlocked {
            levelProgress[progressIndex].state = .inProgress
            persistProgress()
        }
        let session = GameSession(level: level, settings: settings)
        session.statusHandler = { [weak self] status in
            guard status == .won else { return }
            self?.recordVictory(for: level)
        }
        let scene = LaserGameScene(level: level, session: session, settings: settings)
        scene.scaleMode = .resizeFill
        activeGame = GameRuntime(level: level, session: session, scene: scene)
        screen = .gameplay
    }
    
    func playLevel(_ level: Level) {
        // Play a level from the editor without progress tracking
        let session = GameSession(level: level, settings: settings)
        let scene = LaserGameScene(level: level, session: session, settings: settings)
        scene.scaleMode = .resizeFill
        activeGame = GameRuntime(level: level, session: session, scene: scene)
        screen = .gameplay
    }

    func pauseGame() {
        guard let runtime = activeGame,
              runtime.session.status == .running else { return }
        runtime.session.status = .paused
        runtime.scene.setScenePaused(true)
    }
    
    func resumeGame() {
        guard let runtime = activeGame,
              runtime.session.status == .paused else { return }
        runtime.session.status = .running
        runtime.scene.setScenePaused(false)
    }
    
    func retryActiveLevel() {
        guard let level = activeGame?.level else { return }
        startLevel(level)
    }
    
    func exitGameplay() {
        activeGame?.scene.setScenePaused(false)
        activeGame = nil
        screen = .levelSelect
    }
    
    func continueAfterVictory() {
        guard let current = activeGame?.level else {
            exitGameplay()
            return
        }
        if let next = nextLevel(after: current) {
            startLevel(next)
        } else {
            exitGameplay()
        }
    }
    
    func levelPackEntries() -> [LevelPackProgress] {
        normalizePackUnlockStates()
        let progressMap = Dictionary(levelProgress.map { (progressKey(for: $0.level), $0) }) { existing, new in
            existing.state == .completed ? existing : new
        }
        return levelPacks.compactMap { pack in
            let entries = pack.levels.map { level in
                let key = progressKey(for: level)
                return progressMap[key] ?? LevelProgress(level: level, state: .locked)
            }
            guard !entries.isEmpty else { return nil }
            return LevelPackProgress(pack: pack, levels: entries)
        }
    }
    
    func state(for level: Level) -> LevelProgress.State {
        levelProgress.first(where: { $0.level == level })?.state ?? .locked
    }
    
    func nextLevel(after level: Level) -> Level? {
        guard let index = levels.firstIndex(of: level),
              index + 1 < levels.count else { return nil }
        return levels[index + 1]
    }
    
    func reloadLevels(unlocking level: Level? = nil) {
        do {
            try reloadLevelsInternal(unlocking: level)
            loadErrorMessage = nil
        } catch {
            loadErrorMessage = String(describing: error)
        }
    }
    
    private func recordVictory(for level: Level) {
        guard let idx = indexOfLevel(level, in: levelProgress) else { return }
        var updated = levelProgress
        guard updated[idx].state != .completed else { return }
        updated[idx].state = .completed
        unlockNextLevel(from: idx, in: &updated)
        unlockLevels(withIDs: level.unlocks ?? [], progress: &updated)
        unlockNextPackIfNeeded(afterCompleting: level, progress: &updated)
        levelProgress = updated
        persistProgress()
    }
    
    private func unlockNextLevel(from index: Int, in progress: inout [LevelProgress]) {
        guard index + 1 < progress.count else { return }
        if progress[index + 1].state == .locked {
            progress[index + 1].state = .unlocked
        }
    }
    
    private func unlockNextPackIfNeeded(afterCompleting level: Level, progress: inout [LevelProgress]) {
        guard let packIndex = levelPacks.firstIndex(where: { $0.levels.contains(level) }) else { return }
        let completedPackLevels = levelPacks[packIndex].levels
        let isPackComplete = completedPackLevels.allSatisfy { packLevel in
            progress.first(where: { progressKey(for: $0.level) == progressKey(for: packLevel) })?.state == .completed
        }
        guard isPackComplete else { return }
        let nextPackIndex = packIndex + 1
        guard nextPackIndex < levelPacks.count else { return }
        let nextPack = levelPacks[nextPackIndex]
        for level in nextPack.levels {
            if let idx = indexOfLevel(level, in: progress),
               progress[idx].state == .locked {
                progress[idx].state = .unlocked
                break
            }
        }
    }
    
    private func unlockLevels(withIDs ids: [String], progress: inout [LevelProgress]) {
        guard !ids.isEmpty else { return }
        for targetID in ids {
            guard let index = progress.firstIndex(where: { level($0.level, matchesIdentifier: targetID) }) else { continue }
            if progress[index].state == .locked {
                progress[index].state = .unlocked
            }
        }
    }
    
    func resetProgress() {
        guard !levels.isEmpty else { return }
        levelProgress = levels.enumerated().map { index, level in
            LevelProgress(level: level, state: index == 0 ? .unlocked : .locked)
        }
        settings = GameSettings()
        persistProgress()
        activeGame = nil
        screen = .mainMenu
    }
    
    func unlockAllLevels() {
        guard !levels.isEmpty else { return }
        levelProgress = levels.map { LevelProgress(level: $0, state: .completed) }
        persistProgress()
    }
    
    private func persistProgress() {
        progressStore.saveProgress(levelProgress)
    }
    
    private func normalizePackUnlockStates() {
        var updated = levelProgress
        var changed = false
        var previousPackCompleted = true
        
        for (index, pack) in levelPacks.enumerated() {
            var packCompleted = true
            var firstLockedLevelIndex: Int?
            var hasProgress = false
            
            for level in pack.levels {
                guard let progressIndex = indexOfLevel(level, in: updated) else { continue }
                let state = updated[progressIndex].state
                if state != .locked {
                    hasProgress = true
                }
                if state != .completed {
                    packCompleted = false
                    if firstLockedLevelIndex == nil {
                        firstLockedLevelIndex = progressIndex
                    }
                }
            }
            
            let isFirstPack = index == 0
            let packUnlocked = isFirstPack || previousPackCompleted || hasProgress
            if packUnlocked, let lockedIndex = firstLockedLevelIndex, updated[lockedIndex].state == .locked {
                updated[lockedIndex].state = .unlocked
                changed = true
            }
            previousPackCompleted = packCompleted
        }
        
        if changed {
            levelProgress = updated
            persistProgress()
        }
    }
    
    private func progressKey(for level: Level) -> String {
        level.uuid?.uuidString ?? level.id
    }

    private func level(_ level: Level, matchesIdentifier identifier: String) -> Bool {
        if let uuidString = level.uuid?.uuidString,
           uuidString.caseInsensitiveCompare(identifier) == .orderedSame {
            return true
        }
        return level.id == identifier
    }
    
    private func indexOfLevel(_ level: Level, in progress: [LevelProgress]) -> Int? {
        let key = progressKey(for: level)
        return progress.firstIndex { progressKey(for: $0.level) == key }
    }
    
    func presentImportSheet(initialPayload: String?) {
        importSheetState = ImportSheetState(initialPayload: initialPayload)
    }
    
    func dismissImportSheet() {
        importSheetState = nil
    }
    
    func handleImportSuccess(level: Level) {
        reloadLevels(unlocking: level)
    }
    
    func deleteDownloadedLevel(_ level: Level) {
        do {
            let deleted = try LevelRepository.deleteDownloadedLevel(uuid: level.uuid, id: level.id)
            if deleted {
                reloadLevels()
            }
        } catch {
            loadErrorMessage = String(describing: error)
        }
    }
    
    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "laserfingers" else { return }
        let host = url.host?.lowercased()
        switch host {
        case "level":
            if let payload = payload(from: url) {
                presentImportSheet(initialPayload: payload)
            }
        default:
            break
        }
    }
    
    private func payload(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let dataItem = components?.queryItems?.first(where: { $0.name == "data" }),
           let value = dataItem.value,
           !value.isEmpty {
            return value.removingPercentEncoding ?? value
        }
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        return decoded
    }
    
    private func reloadLevelsInternal(unlocking level: Level?) throws {
        let loadedPacks = try LevelRepository.load()
        levelPacks = loadedPacks
        levels = loadedPacks.flatMap { $0.levels }
        var progress = progressStore.loadProgress(for: levels)
        if let level,
           let index = indexOfLevel(level, in: progress),
           progress[index].state == .locked {
            progress[index].state = .unlocked
        }
        levelProgress = progress
    }
}

struct GameRuntime {
    let id = UUID()
    let level: Level
    let session: GameSession
    let scene: LaserGameScene
}

struct LevelProgress: Identifiable {
    enum State: String, Codable {
        case locked
        case unlocked
        case inProgress
        case completed
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            self = State(rawValue: rawValue) ?? .locked
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }
    
    let level: Level
    var state: State
    
    var id: String { level.uuid?.uuidString ?? level.id }
}

struct LevelPackProgress: Identifiable {
    let pack: LevelPack
    let levels: [LevelProgress]
    
    var id: String { pack.id }
    var completedCount: Int {
        levels.filter { $0.state == .completed }.count
    }
    var totalCount: Int { levels.count }
    var state: LevelProgress.State {
        guard !levels.isEmpty else { return .locked }
        if levels.allSatisfy({ $0.state == .locked }) { return .locked }
        if levels.allSatisfy({ $0.state == .completed }) { return .completed }
        if levels.contains(where: { $0.state == .inProgress }) { return .inProgress }
        return .unlocked
    }
}

enum GameResult {
    case victory
    case defeat
}

struct ImportSheetState: Identifiable {
    let id = UUID()
    let initialPayload: String?
}

final class GameSession: ObservableObject {
    enum Status {
        case loading
        case running
        case paused
        case won
        case lost
    }
    
    let level: Level
    @Published var status: Status = .loading {
        didSet {
            if status != oldValue {
                statusHandler?(status)
            }
        }
    }
    @Published var touchAllowance: Int
    let initialTouchAllowance: Int
    @Published var activeTouches: Int = 0
    @Published var fillPercentage: CGFloat = 0
    @Published var zapCount: Int = 0
    let maxLives: Int
    @Published var remainingLives: Int
    let soundEnabled: Bool
    let hapticsEnabled: Bool
    let hasInfiniteSlots: Bool
    
    var statusHandler: ((Status) -> Void)?
    
    init(level: Level, settings: GameSettings) {
        self.level = level
        let hardwareLimit = TouchCapabilities.maxSimultaneousTouches
        let requestedTouches = level.maxTouches ?? hardwareLimit
        let effectiveAllowance = max(1, min(requestedTouches, hardwareLimit))
        self.touchAllowance = effectiveAllowance
        self.initialTouchAllowance = effectiveAllowance
        let requestedLives = level.lives ?? 1
        self.maxLives = max(1, requestedLives)
        self.remainingLives = self.maxLives
        self.soundEnabled = settings.soundEnabled
        self.hapticsEnabled = settings.hapticsEnabled
        self.hasInfiniteSlots = settings.infiniteSlotsEnabled
    }
    
    func registerZap() -> Bool {
        guard status == .running else { return false }
        zapCount += 1
        remainingLives = max(0, remainingLives - 1)
        return remainingLives == 0
    }
}
