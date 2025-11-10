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
    }
    
    @Published var screen: Screen = .mainMenu
    @Published var settings = GameSettings()
    @Published private(set) var levelProgress: [LevelProgress]
    @Published var activeGame: GameRuntime?
    
    private let levels: [Level]
    
    init() {
        let loadedLevels = LevelRepository.load()
        self.levels = loadedLevels.isEmpty ? Level.fallback : loadedLevels
        self.levelProgress = levels.enumerated().map { index, level in
            LevelProgress(level: level, state: index == 0 ? .current : .locked)
        }
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
    
    func showLevelSelect() {
        screen = .levelSelect
    }
    
    func startLevel(_ level: Level) {
        guard state(for: level) != .locked else { return }
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
    
    func levelProgressEntries() -> [LevelProgress] {
        levelProgress
    }
    
    func state(for level: Level) -> LevelProgress.State {
        levelProgress.first(where: { $0.level == level })?.state ?? .locked
    }
    
    func nextLevel(after level: Level) -> Level? {
        guard let index = levels.firstIndex(of: level),
              index + 1 < levels.count else { return nil }
        return levels[index + 1]
    }
    
    private func recordVictory(for level: Level) {
        guard let idx = levelProgress.firstIndex(where: { $0.level.id == level.id }) else { return }
        var updated = levelProgress
        if updated[idx].state != .completed {
            updated[idx].state = .completed
            if idx + 1 < updated.count && updated[idx + 1].state == .locked {
                updated[idx + 1].state = .current
            }
            levelProgress = updated
        }
    }
}

struct GameRuntime {
    let id = UUID()
    let level: Level
    let session: GameSession
    let scene: LaserGameScene
}

struct GameSettings {
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
}

struct LevelProgress: Identifiable {
    enum State {
        case locked
        case current
        case completed
    }
    
    let level: Level
    var state: State
    
    var id: Int { level.id }
}

enum GameResult {
    case victory
    case defeat
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
    let soundEnabled: Bool
    let hapticsEnabled: Bool
    
    var statusHandler: ((Status) -> Void)?
    
    init(level: Level, settings: GameSettings) {
        self.level = level
        self.touchAllowance = level.allowedTouches
        self.initialTouchAllowance = level.allowedTouches
        self.soundEnabled = settings.soundEnabled
        self.hapticsEnabled = settings.hapticsEnabled
    }
    
    func registerZap() -> Bool {
        guard status == .running else { return false }
        zapCount += 1
        if touchAllowance > 0 {
            touchAllowance -= 1
        }
        return touchAllowance == 0
    }
}
