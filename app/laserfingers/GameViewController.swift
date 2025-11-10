//
//  RootContainerView.swift
//  laserfingers
//
//  Created by Zach Snow on 11/9/25.
//

import SwiftUI
import SpriteKit

struct RootContainerView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        Group {
            switch coordinator.screen {
            case .mainMenu:
                MainMenuView()
            case .settings:
                SettingsView()
            case .about:
                AboutView()
            case .levelSelect:
                LevelSelectView()
            case .gameplay:
                if let runtime = coordinator.activeGame {
                    GameplayView(runtime: runtime)
                } else {
                    MainMenuView()
                }
            }
        }
        .animation(.easeInOut, value: coordinator.screen)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Main Menu

struct MainMenuView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        ZStack {
            SpriteView(scene: backgroundScene, options: [.allowsTransparency])
                .ignoresSafeArea()
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Text("LASERFINGERS")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .kerning(4)
                    .foregroundColor(.white)
                VStack(spacing: 16) {
                    LaserButton(title: "Play") { coordinator.showLevelSelect() }
                    LaserButton(title: "Settings") { coordinator.showSettings() }
                    LaserButton(title: "About") { coordinator.showAbout() }
                }
                .frame(maxWidth: 320)
                Text("Dodge the beams. Fill the gate.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
            }
            .padding(32)
        }
    }
}

// MARK: - Settings & About

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        MenuScaffold(scene: backgroundScene) {
            VStack(spacing: 24) {
                Text("Settings")
                    .font(.title.bold())
                Toggle("Sound Effects", isOn: $coordinator.settings.soundEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                Toggle("Haptics", isOn: $coordinator.settings.hapticsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                Spacer()
                LaserButton(title: "Back") { coordinator.goToMainMenu() }
            }
        }
    }
}

struct AboutView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        MenuScaffold(scene: backgroundScene) {
            VStack(spacing: 16) {
                Text("About")
                    .font(.title.bold())
                Text("Laserfingers is by x0xrx. Inspired by Slice HD and a craving for tactile laser dodging.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                Link("See also Gernal →", destination: URL(string: "https://x0xrx.com")!)
                    .foregroundColor(.pink)
                Spacer()
                LaserButton(title: "Back") { coordinator.goToMainMenu() }
            }
        }
    }
}

// MARK: - Level Select

struct LevelSelectView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        ZStack {
            SpriteView(scene: backgroundScene, options: [.allowsTransparency])
                .ignoresSafeArea()
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Button(action: coordinator.goToMainMenu) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)
                    Spacer()
                    Text("Level Select")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Spacer().frame(width: 44)
                }
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(coordinator.levelProgressEntries()) { entry in
                            LevelRow(entry: entry) {
                                coordinator.startLevel(entry.level)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct LevelRow: View {
    let entry: LevelProgress
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.level.title)
                        .font(.headline)
                    Text(entry.level.description)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                statusIcon
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(entry.state == .locked)
        .opacity(entry.state == .locked ? 0.4 : 1)
    }
    
    private var statusIcon: some View {
        switch entry.state {
        case .completed:
            return Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
        case .current:
            return Image(systemName: "arrowtriangle.right.circle.fill")
                .foregroundColor(.yellow)
        case .locked:
            return Image(systemName: "lock.fill")
                .foregroundColor(.gray)
        }
    }
    
    private var borderColor: Color {
        switch entry.state {
        case .completed: return .green.opacity(0.4)
        case .current: return .yellow.opacity(0.6)
        case .locked: return .white.opacity(0.2)
        }
    }
}

// MARK: - Gameplay

struct GameplayView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    let runtime: GameRuntime
    @ObservedObject private var session: GameSession
    
    init(runtime: GameRuntime) {
        self.runtime = runtime
        self._session = ObservedObject(initialValue: runtime.session)
    }
    
    var body: some View {
        ZStack {
            GameSpriteView(scene: runtime.scene)
                .id(runtime.level.id)
                .ignoresSafeArea()
            VStack {
                HStack(alignment: .top) {
                    GameHUDView(session: session)
                    Spacer()
                    PauseButton(isEnabled: session.status == .running) {
                        coordinator.pauseGame()
                    }
                }
                .padding()
                Spacer()
            }
            overlayView
        }
    }
    
    @ViewBuilder
    private var overlayView: some View {
        switch session.status {
        case .lost:
            lostOverlay
        case .won:
            winOverlay
        case .paused:
            PauseOverlay(
                resumeAction: coordinator.resumeGame,
                exitAction: coordinator.exitGameplay
            )
        default:
            EmptyView()
        }
    }
    
    private var lostOverlay: some View {
        ResultOverlay(
            title: "Zapped!",
            message: "You ran out of touches.",
            primaryTitle: "Try Again",
            primaryAction: { coordinator.retryActiveLevel() },
            secondaryTitle: "Exit",
            secondaryAction: { coordinator.exitGameplay() }
        )
    }
    
    private var winOverlay: some View {
        ResultOverlay(
            title: "Gate Open",
            message: "Level complete.",
            primaryTitle: hasNextLevel ? "Next Level" : "Level Select",
            primaryAction: {
                if hasNextLevel {
                    coordinator.continueAfterVictory()
                } else {
                    coordinator.exitGameplay()
                }
            },
            secondaryTitle: "Level Select",
            secondaryAction: { coordinator.exitGameplay() }
        )
    }
    
    private var hasNextLevel: Bool {
        coordinator.nextLevel(after: runtime.level) != nil
    }
}

struct GameHUDView: View {
    @ObservedObject var session: GameSession
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Level \(session.level.id)")
                    .font(.headline)
                Text(session.level.title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Active: \(session.activeTouches)")
                Text("Slots left: \(session.touchAllowance)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding()
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ResultOverlay: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    let secondaryTitle: String
    let secondaryAction: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.75))
                LaserButton(title: primaryTitle, action: primaryAction)
                Button(secondaryTitle, action: secondaryAction)
                    .padding(.top, 8)
            }
            .padding()
            .frame(maxWidth: 320)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

struct PauseOverlay: View {
    let resumeAction: () -> Void
    let exitAction: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Paused")
                    .font(.largeTitle.bold())
                Text("Take a breath, lasers will wait.")
                    .foregroundColor(.white.opacity(0.8))
                HStack(spacing: 16) {
                    Button(action: resumeAction) {
                        Label("Resume", systemImage: "play.fill")
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: exitAction) {
                        Label("Exit", systemImage: "rectangle.portrait.and.arrow.right")
                            .padding()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: 380)
            }
            .padding(32)
            .background(Color.black.opacity(0.8))
            .cornerRadius(24)
            .shadow(color: .black.opacity(0.4), radius: 20)
            .padding()
        }
    }
}

struct PauseButton: View {
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(isEnabled ? .white : .gray)
                .padding(8)
        }
        .disabled(!isEnabled)
        .background(Color.white.opacity(0.1))
        .clipShape(Circle())
    }
}

// MARK: - Shared UI

struct MenuScaffold<Content: View>: View {
    @State private var scene: MenuBackgroundScene
    let content: Content
    
    init(scene: MenuBackgroundScene, @ViewBuilder content: () -> Content) {
        self._scene = State(initialValue: scene)
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.allowsTransparency])
                .ignoresSafeArea()
            Color.black.opacity(0.6).ignoresSafeArea()
            content
                .padding()
                .frame(maxWidth: 480)
                .background(Color.black.opacity(0.55))
                .cornerRadius(24)
                .padding()
        }
    }
}

struct LaserButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
        .shadow(color: .pink.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}
