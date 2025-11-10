//
//  RootContainerView.swift
//  laserfingers
//
//  Created by Zach Snow on 11/9/25.
//

import SwiftUI
import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct RootContainerView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        ZStack {
            contentView
                .blur(radius: coordinator.loadErrorMessage == nil ? 0 : 8)
                .allowsHitTesting(coordinator.loadErrorMessage == nil)
            if let message = coordinator.loadErrorMessage {
                FatalErrorOverlay(message: message)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: coordinator.screen)
        .animation(.easeInOut, value: coordinator.loadErrorMessage)
        .preferredColorScheme(.dark)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch coordinator.screen {
        case .mainMenu:
            MainMenuView()
        case .settings:
            SettingsView()
        case .about:
            AboutView()
        case .levelSelect:
            LevelSelectView()
        case .advancedMenu:
            AdvancedMenuView()
        case .gameplay:
            if let runtime = coordinator.activeGame {
                GameplayView(runtime: runtime)
            } else {
                MainMenuView()
            }
        }
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
                Text("LASER\nFINGERS")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .kerning(4)
                    .foregroundColor(.white)
                VStack(spacing: 16) {
                    LaserButton(title: "Play") { coordinator.showLevelSelect() }
                    LaserButton(title: "Settings") { coordinator.showSettings() }
                    if coordinator.settings.advancedModeEnabled {
                        LaserButton(title: "Advanced") { coordinator.showAdvancedMenu() }
                    }
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
                Toggle("Advanced Mode", isOn: $coordinator.settings.advancedModeEnabled)
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

struct AdvancedMenuView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        MenuScaffold(scene: backgroundScene) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Advanced Tools")
                    .font(.title.bold())
                Toggle("Infinite Slots", isOn: $coordinator.settings.infiniteSlotsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                    .accessibilityIdentifier("advanced_infinite_slots_toggle")
                VStack(spacing: 12) {
                    LaserButton(title: "Reset Progress") {
                        coordinator.resetProgress()
                    }
                    LaserButton(title: "Unlock All Levels") {
                        coordinator.unlockAllLevels()
                    }
                }
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
                    VStack(spacing: 20) {
                        ForEach(coordinator.levelPackEntries()) { packEntry in
                            LevelPackSection(entry: packEntry) { level in
                                coordinator.startLevel(level)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct LevelPackSection: View {
    let entry: LevelPackProgress
    let startLevel: (Level) -> Void
    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.pack.name)
                    .font(.headline)
                Spacer()
                Text("\(entry.completedCount) of \(entry.totalCount)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(entry.levels) { levelEntry in
                    LevelIconButton(entry: levelEntry) {
                        startLevel(levelEntry.level)
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 1)
        )
    }
    
    private var borderColor: Color {
        switch entry.state {
        case .completed: return .green.opacity(0.4)
        case .inProgress: return .orange.opacity(0.6)
        case .unlocked: return .yellow.opacity(0.6)
        case .locked: return .white.opacity(0.2)
        }
    }
}

struct LevelIconButton: View {
    let entry: LevelProgress
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(tileBackground)
                statusIcon
                    .font(.system(size: 28, weight: .semibold))
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(entry.state == .locked)
        .opacity(entry.state == .locked ? 0.35 : 1)
    }
    
    private var statusIcon: some View {
        switch entry.state {
        case .completed:
            return Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
        case .unlocked:
            return Image(systemName: "arrowtriangle.right.circle.fill")
                .foregroundColor(.yellow)
        case .inProgress:
            return Image(systemName: "clock.fill")
                .foregroundColor(.orange)
        case .locked:
            return Image(systemName: "lock.fill")
                .foregroundColor(.gray)
        }
    }
    
    private var tileBackground: Color {
        switch entry.state {
        case .completed: return Color.green.opacity(0.15)
        case .unlocked: return Color.yellow.opacity(0.15)
        case .inProgress: return Color.orange.opacity(0.15)
        case .locked: return Color.white.opacity(0.08)
        }
    }
}

// MARK: - Error Overlay

struct FatalErrorOverlay: View {
    let message: String
    @State private var didCopy = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("Level Data Failed to Load")
                .font(.title3.weight(.semibold))
            Text("Fix the issue below and relaunch the app.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            ScrollView {
                Text(message)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding()
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            Button(action: copyMessage) {
                Label(didCopy ? "Copied" : "Copy Error", systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        }
        .padding(24)
        .background(Color.black.opacity(0.9))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .padding()
    }
    
    private func copyMessage() {
        let payload = "Level load error:\n\(message)"
        #if os(iOS)
        UIPasteboard.general.string = payload
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        #endif
        withAnimation(.easeInOut(duration: 0.2)) {
            didCopy = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                didCopy = false
            }
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
            SpriteView(scene: runtime.scene)
                .id(runtime.id)
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
                Text("Slots left: \(slotsText)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding()
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    private var slotsText: String {
        session.hasInfiniteSlots ? "∞" : "\(session.touchAllowance)"
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
