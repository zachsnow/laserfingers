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

private let menuContentPadding: CGFloat = 16
private let mainMenuContentWidth: CGFloat = 320

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
        .sheet(item: $coordinator.importSheetState) { state in
            LevelImportSheet(initialPayload: state.initialPayload)
        }
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
        case .levelEditor:
            if let editorViewModel = coordinator.levelEditorViewModel {
                LevelEditorView(viewModel: editorViewModel)
            } else {
                MainMenuView()
            }
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
        MenuScaffold(scene: backgroundScene, showDimOverlay: false) {
            VStack(alignment: .leading, spacing: 32) {
                Spacer()
                Text("LASER\nFINGERS")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .kerning(4)
                    .foregroundColor(.white)
                    .shadow(color: Color.pink.opacity(0.7), radius: 18, x: 0, y: 0)
                    .shadow(color: Color.blue.opacity(0.35), radius: 32, x: 0, y: 0)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: mainMenuContentWidth, alignment: .leading)
                VStack(spacing: 16) {
                    LaserButton(title: "Play") { coordinator.showLevelSelect() }
                    LaserButton(title: "Settings") { coordinator.showSettings() }
                    if coordinator.settings.advancedModeEnabled {
                        LaserButton(title: "Advanced") { coordinator.showAdvancedMenu() }
                    }
                    LaserButton(title: "About") { coordinator.showAbout() }
                }
                .frame(maxWidth: mainMenuContentWidth, alignment: .leading)
                Text("Dodge the beams. Fill the gate.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: mainMenuContentWidth, alignment: .leading)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(menuContentPadding)
        }
    }
}

// MARK: - Settings & About

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        MenuScaffold(scene: backgroundScene, showDimOverlay: true) {
            VStack(spacing: 24) {
                Text("Settings")
                    .font(.title.bold())
                Toggle("Sound Effects", isOn: $coordinator.settings.soundEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                Toggle("Haptics", isOn: $coordinator.settings.hapticsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                Toggle("Advanced Mode", isOn: $coordinator.settings.advancedModeEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Visual Effects")
                        .font(.headline)
                    VisualEffectsToggleList(
                        glowEnabled: $coordinator.settings.glowEnabled,
                        blurEnabled: $coordinator.settings.blurEnabled
                    )
                }
                Spacer()
                LaserButton(title: "Back", style: .secondary) { coordinator.goToMainMenu() }
            }
            .padding(menuContentPadding)
        }
    }
}

struct VisualEffectsToggleList: View {
    @Binding var glowEnabled: Bool
    @Binding var blurEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Laser Glow", isOn: $glowEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .pink))
            Toggle("Bloom Blur", isOn: $blurEnabled)
                .toggleStyle(SwitchToggleStyle(tint: .pink))
        }
    }
}

struct GameplayVisualSettingsSheet: View {
    @Binding var glowEnabled: Bool
    @Binding var blurEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Visual Effects") {
                    VisualEffectsToggleList(
                        glowEnabled: $glowEnabled,
                        blurEnabled: $blurEnabled
                    )
                }
            }
            .navigationTitle("Visual Effects")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AboutView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    private let buildInfo = BuildInfo.current()
    
    var body: some View {
        MenuScaffold(scene: backgroundScene, showDimOverlay: true) {
            VStack(spacing: 16) {
                Text("About")
                    .font(.title.bold())
                Text("Laserfingers is by x0xrx. Inspired by Slice HD and a craving for tactile laser dodging.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                Link("See also Gernal →", destination: URL(string: "https://x0xrx.com")!)
                    .foregroundColor(.pink)
                BuildInfoSection(buildInfo: buildInfo)
                Spacer()
                LaserButton(title: "Back", style: .secondary) { coordinator.goToMainMenu() }
            }
            .padding(menuContentPadding)
        }
    }
}

struct BuildInfoSection: View {
    let buildInfo: BuildInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Build Info")
                .font(.headline)
            BuildInfoRow(label: "Version", value: buildInfo.version)
            BuildInfoRow(label: "Build", value: buildInfo.buildNumber)
            BuildInfoRow(label: "Built On", value: buildInfo.formattedBuildDate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

private struct BuildInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(.white)
        }
    }
}

struct AdvancedMenuView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        MenuScaffold(scene: backgroundScene, showDimOverlay: true) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Advanced Tools")
                    .font(.title.bold())
                Toggle("Infinite Slots", isOn: $coordinator.settings.infiniteSlotsEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: .pink))
                    .accessibilityIdentifier("advanced_infinite_slots_toggle")
                LaserButton(title: "Level Editor") {
                    coordinator.openLevelEditor(with: nil)
                }
                LaserButton(title: "Import Level Code") {
                    coordinator.presentImportSheet(initialPayload: nil)
                }
                LaserButton(title: "Reset") {
                    coordinator.resetProgress()
                }
                LaserButton(title: "Unlock All Levels") {
                    coordinator.unlockAllLevels()
                }
                Spacer()
                LaserButton(title: "Back", style: .secondary) { coordinator.goToMainMenu() }
            }
            .padding(menuContentPadding)
        }
    }
}

// MARK: - Level Select

struct LevelSelectView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var backgroundScene = MenuBackgroundScene()
    
    var body: some View {
        MenuScaffold(scene: backgroundScene) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Level Select")
                    .font(.title.bold())
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(coordinator.levelPackEntries()) { packEntry in
                            let isDownloaded = LevelRepository.isDownloadedPack(packEntry.pack)
                            LevelPackSection(
                                entry: packEntry,
                                isDownloadedPack: isDownloaded,
                                startLevel: { level in
                                    coordinator.startLevel(level)
                                },
                                deleteLevel: isDownloaded ? { level in
                                    coordinator.deleteDownloadedLevel(level)
                                } : nil
                            )
                        }
                    }
                }
                LaserButton(title: "Back", style: .secondary) {
                    coordinator.goToMainMenu()
                }
            }
            .padding(menuContentPadding)
        }
    }
}

struct LevelPackSection: View {
    let entry: LevelPackProgress
    let isDownloadedPack: Bool
    let startLevel: (Level) -> Void
    let deleteLevel: ((Level) -> Void)?
    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 12)]
    
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
                    LevelIconButton(
                        entry: levelEntry,
                        action: { startLevel(levelEntry.level) },
                        deleteAction: isDownloadedPack ? {
                            deleteLevel?(levelEntry.level)
                        } : nil
                    )
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
    let deleteAction: (() -> Void)?
    @EnvironmentObject private var coordinator: AppCoordinator
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    
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
        .contextMenu {
            if coordinator.settings.advancedModeEnabled {
                Button {
                    copyIdentifier(entry.level.id)
                } label: {
                    Label("ID: \(entry.level.id)", systemImage: "number")
                }
                if let uuidString = entry.level.uuid?.uuidString {
                    Button {
                        copyIdentifier(uuidString)
                    } label: {
                        Label("UUID: \(uuidString)", systemImage: "circle.grid.2x2")
                    }
                } else {
                    Label("UUID: Not Set", systemImage: "circle.grid.2x2")
                        .foregroundColor(.white.opacity(0.6))
                }
                Button {
                    coordinator.openLevelEditor(with: entry.level)
                } label: {
                    Label("Edit in Level Editor", systemImage: "pencil.and.outline")
                }
                Button {
                    copyLevelJSON(entry.level)
                } label: {
                    Label("Copy Level JSON", systemImage: "doc.on.doc")
                }
            }
            if let deleteAction {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
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
    
    private func copyLevelJSON(_ level: Level) {
        guard let data = try? encoder.encode(level),
              let json = String(data: data, encoding: .utf8) else { return }
        copyToPasteboard(json)
    }

    private func copyIdentifier(_ value: String) {
        copyToPasteboard(value)
    }

    private func copyToPasteboard(_ string: String) {
#if os(iOS)
        UIPasteboard.general.string = string
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
#endif
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
    @State private var showVisualSettings = false
    
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
                        .allowsHitTesting(false)
                    Spacer()
                    if coordinator.settings.advancedModeEnabled {
                        Button {
                            showVisualSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title2)
                                .padding(10)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 6)
                    }
                    PauseButton(isEnabled: session.status == .running) {
                        coordinator.pauseGame()
                    }
                }
                .padding()
                Spacer()
            }
            overlayView
        }
        .sheet(isPresented: $showVisualSettings) {
            GameplayVisualSettingsSheet(
                glowEnabled: $coordinator.settings.glowEnabled,
                blurEnabled: $coordinator.settings.blurEnabled
            )
        }
        .onAppear(perform: applyVisualSettings)
        .onChange(of: coordinator.settings.glowEnabled) { applyVisualSettings() }
        .onChange(of: coordinator.settings.blurEnabled) { applyVisualSettings() }
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
                restartAction: { coordinator.retryActiveLevel() },
                exitAction: coordinator.exitGameplay
            )
        default:
            EmptyView()
        }
    }
    
    private var lostOverlay: some View {
        DefeatOverlay(
            title: "Zapped!",
            message: "You ran out of lives.",
            retryAction: { coordinator.retryActiveLevel() },
            exitAction: { coordinator.exitGameplay() }
        )
    }
    
    private var winOverlay: some View {
        VictoryOverlay(
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
            restartAction: { coordinator.retryActiveLevel() },
            exitAction: { coordinator.exitGameplay() }
        )
    }
    
    private var hasNextLevel: Bool {
        coordinator.nextLevel(after: runtime.level) != nil
    }
    
    private func applyVisualSettings() {
        runtime.scene.applyVisualSettings(coordinator.settings)
    }
}

struct GameHUDView: View {
    @ObservedObject var session: GameSession
    private let hudTextShadowColor = Color.black.opacity(0.85)
    
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.level.title)
                    .font(.headline)
                    .shadow(color: hudTextShadowColor, radius: 2, x: 0, y: 1)
                Text(session.level.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.75))
                    .shadow(color: hudTextShadowColor, radius: 2, x: 0, y: 1)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                livesView
                if let concurrency = concurrencyText {
                    Text(concurrency)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .shadow(color: hudTextShadowColor, radius: 2, x: 0, y: 1)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private var livesView: some View {
        HStack(spacing: 6) {
            ForEach(0..<session.maxLives, id: \.self) { index in
                Circle()
                    .fill(index < session.remainingLives ? Color.white : Color.clear)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    )
            }
        }
    }
    
    private var concurrencyText: String? {
        if session.hasInfiniteSlots {
            return "Concurrency: ∞"
        }
        let deviceMax = TouchCapabilities.maxSimultaneousTouches
        guard session.initialTouchAllowance < deviceMax else {
            return nil
        }
        return "Concurrency: \(session.initialTouchAllowance)"
    }
}

struct VictoryOverlay: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    let restartAction: () -> Void
    let exitAction: () -> Void
    
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
                HStack(spacing: 12) {
                    LaserButton(title: "Restart", style: .secondary, action: restartAction)
                    LaserButton(title: "Exit", style: .secondary, action: exitAction)
                }
            }
            .padding()
            .frame(maxWidth: 360)
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

struct DefeatOverlay: View {
    let title: String
    let message: String
    let retryAction: () -> Void
    let exitAction: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.75))
                LaserButton(title: "Try Again", action: retryAction)
                LaserButton(title: "Exit", style: .secondary, action: exitAction)
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
    let restartAction: () -> Void
    let exitAction: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Paused")
                    .font(.largeTitle.bold())
                Text("Take a breath, lasers will wait.")
                    .foregroundColor(.white.opacity(0.8))
                LaserButton(title: "Resume", action: resumeAction)
                HStack(spacing: 12) {
                    LaserButton(title: "Restart", style: .secondary, action: restartAction)
                    LaserButton(title: "Exit", style: .secondary, action: exitAction)
                }
            }
            .padding(menuContentPadding)
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
    let showDimOverlay: Bool
    
    init(scene: MenuBackgroundScene, showDimOverlay: Bool = true, @ViewBuilder content: () -> Content) {
        self._scene = State(initialValue: scene)
        self.showDimOverlay = showDimOverlay
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            SpriteView(scene: scene, options: [.allowsTransparency])
                .ignoresSafeArea()
            if showDimOverlay {
                Color.black.opacity(0.55)
                    .blendMode(.multiply)
                    .ignoresSafeArea()
            }
            content
                .padding(menuContentPadding)
                .frame(maxWidth: 520)
                .padding(menuContentPadding)
        }
    }
}

struct LevelImportSheet: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var payload: String
    @State private var statusMessage: String?
    @State private var statusColor: Color = .white.opacity(0.8)
    @State private var importSuccess: Level?
    @State private var pendingConflictImport: LevelImportManager.PreparedImport?
    @State private var showConflictDialog = false
    @State private var isProcessing = false
    
    private var importManager = LevelImportManager()
    private let initialPayload: String?
    
    init(initialPayload: String?) {
        self.initialPayload = initialPayload
        _payload = State(initialValue: initialPayload ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 20) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Paste a level JSON blob or a Base64 share code below.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.8))
                        TextEditor(text: $payload)
                            .frame(minHeight: 220)
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.15))
                            )
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.asciiCapable)
                            if let message = statusMessage {
                                Text(message)
                                    .foregroundColor(statusColor)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.vertical, 4)
                                    .id("ImportStatusMessage")
                            }
                            if let level = importSuccess {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Imported “\(level.title)”")
                                        .font(.headline)
                                        .id("ImportSuccessMessage")
                                    Button {
                                        startImportedLevel(level)
                                    } label: {
                                        Label("Play Now", systemImage: "play.fill")
                                            .font(.headline)
                                            .padding()
                                            .frame(maxWidth: .infinity)
                                            .background(LinearGradient(
                                                colors: [.pink, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .foregroundColor(.white)
                                            .cornerRadius(16)
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Button("Cancel") {
                            closeSheet()
                        }
                        .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    Button(action: startImport) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .frame(width: 24, height: 24)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 24)
                            } else {
                                Text("Import Level")
                                    .font(.headline)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                            }
                        }
                        .disabled(payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
                        .background(isProcessing ? Color.white.opacity(0.15) : Color.pink)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding()
                .onChange(of: statusMessage) {
                    withAnimation {
                        proxy.scrollTo("ImportStatusMessage", anchor: .bottom)
                    }
                }
                .onChange(of: importSuccessKey) {
                    if importSuccess != nil {
                        withAnimation {
                            proxy.scrollTo("ImportSuccessMessage", anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle("Import Level")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        closeSheet()
                    }
                }
            }
            .confirmationDialog("Level already exists", isPresented: $showConflictDialog, presenting: pendingConflictImport) { prepared in
                Button("Overwrite", role: .destructive) {
                    pendingConflictImport = nil
                    finalizeImport(prepared: prepared, overwrite: true)
                }
                Button("Create New Copy") {
                    pendingConflictImport = nil
                    finalizeImport(prepared: prepared, overwrite: false)
                }
                Button("Cancel", role: .cancel) {
                    pendingConflictImport = nil
                }
            } message: { prepared in
                Text("“\(prepared.level.title)” already exists in Downloaded. Overwrite it or create a new copy?")
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isProcessing)
    }
    
    private func startImport() {
        statusMessage = nil
        importSuccess = nil
        pendingConflictImport = nil
        showConflictDialog = false
        do {
            let prepared = try importManager.prepareImport(from: payload)
            if prepared.match != nil {
                pendingConflictImport = prepared
                showConflictDialog = true
                return
            }
            finalizeImport(prepared: prepared, overwrite: false)
        } catch {
            statusMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusColor = .red
            isProcessing = false
        }
    }
    
    private func finalizeImport(prepared: LevelImportManager.PreparedImport, overwrite: Bool) {
        isProcessing = true
        do {
            let savedLevel = try importManager.persist(prepared, overwrite: overwrite)
            coordinator.handleImportSuccess(level: savedLevel)
            statusMessage = "Imported “\(savedLevel.title)” successfully."
            statusColor = .green
            importSuccess = savedLevel
            payload = ""
        } catch {
            statusMessage = error.localizedDescription
            statusColor = .red
        }
        isProcessing = false
    }
    
    private func startImportedLevel(_ level: Level) {
        if let uuid = level.uuid,
           let entry = coordinator.levelProgress.first(where: { $0.level.uuid == uuid }) {
            coordinator.startLevel(entry.level)
            closeSheet()
            return
        }
        if let entry = coordinator.levelProgress.first(where: { $0.level.id == level.id }) {
            coordinator.startLevel(entry.level)
            closeSheet()
        }
    }
    
    private func closeSheet() {
        coordinator.dismissImportSheet()
        dismiss()
    }
    
    private var importSuccessKey: String? {
        importSuccess?.uuid?.uuidString ?? importSuccess?.id
    }
    
}

struct LaserButton: View {
    enum Style {
        case primary
        case secondary
    }
    
    let title: String
    let style: Style
    let action: () -> Void
    
    init(title: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(textColor)
                .background(backgroundView)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(borderColor, lineWidth: style == .secondary ? 1.5 : 0)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .shadow(color: style == .primary ? Color.pink.opacity(0.4) : .clear, radius: 8, x: 0, y: 4)
    }
    
    private var backgroundView: some View {
        Group {
            if style == .primary {
                LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color.clear
            }
        }
    }
    
    private var textColor: Color {
        style == .primary ? .white : .pink
    }
    
    private var borderColor: Color {
        style == .secondary ? Color.pink.opacity(0.9) : .clear
    }
}
