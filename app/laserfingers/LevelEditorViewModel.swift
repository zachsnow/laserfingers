import Foundation
import CoreGraphics
import Combine

final class LevelEditorViewModel: ObservableObject, Identifiable {
    enum Mode {
        case creating
        case editing(Level)
    }
    
    enum Tool: String, CaseIterable, Identifiable {
        case circle
        case square
        case sweeper
        case segment
        case rotor
        
        var id: String { rawValue }
        
        var iconName: String {
            switch self {
            case .circle: return "circle"
            case .square: return "square"
            case .sweeper: return "line.3.horizontal"
            case .segment: return "line.diagonal"
            case .rotor: return "gyroscope"
            }
        }
        
        var displayName: String {
            switch self {
            case .circle: return "Circle"
            case .square: return "Square"
            case .sweeper: return "Sweeper"
            case .segment: return "Segment"
            case .rotor: return "Rotor"
            }
        }
    }
    
    enum PlaybackState {
        case paused
        case playing
    }
    
    enum FileMenuItem: String, CaseIterable, Identifiable {
        case settings
        case options
        case share
        case reset
        case exit
        
        var id: String { rawValue }
        
        var label: String {
            switch self {
            case .settings: return "Settings"
            case .options: return "Options"
            case .share: return "Share"
            case .reset: return "Reset"
            case .exit: return "Exit"
            }
        }
        
        var iconName: String {
            switch self {
            case .settings: return "gear"
            case .options: return "slider.horizontal.3"
            case .share: return "square.and.arrow.up"
            case .reset: return "arrow.counterclockwise"
            case .exit: return "xmark.circle"
            }
        }
        
        var isDestructive: Bool {
            switch self {
            case .reset, .exit:
                return true
            default:
                return false
            }
        }
    }
    
    struct EditorOptions {
        var snapEnabled: Bool = true
        var snapInterval: CGFloat = 0.1
    }
    
    struct EditorLevelSnapshot: Identifiable, Equatable {
        enum BackgroundStyle: Equatable {
            case gradient
            case asset(name: String)
        }
        
        var id: String
        var title: String
        var description: String
        var buttons: [Level.Button]
        var lasers: [Level.Laser]
        var background: BackgroundStyle
        var uuid: UUID?
        
        init(
            id: String,
            title: String,
            description: String,
            buttons: [Level.Button],
            lasers: [Level.Laser],
            background: BackgroundStyle,
            uuid: UUID?
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.buttons = buttons
            self.lasers = lasers
            self.background = background
            self.uuid = uuid
        }
        
        init(level: Level) {
            self.init(
                id: level.id,
                title: level.title,
                description: level.description,
                buttons: level.buttons,
                lasers: level.lasers,
                background: level.backgroundImage.map { .asset(name: $0) } ?? .gradient,
                uuid: level.uuid
            )
        }
        
        static func blank() -> EditorLevelSnapshot {
            EditorLevelSnapshot(
                id: "new-level",
                title: "Untitled Level",
                description: "Use the tools to start building.",
                buttons: [],
                lasers: [],
                background: .gradient,
                uuid: UUID()
            )
        }
    }
    
    enum Selection: Identifiable, Equatable {
        case button(buttonID: String, hitAreaID: String?)
        case laser(laserID: String)
        
        var id: String {
            switch self {
            case .button(let buttonID, let hitAreaID):
                return "button-\(buttonID)-\(hitAreaID ?? "root")"
            case .laser(let laserID):
                return "laser-\(laserID)"
            }
        }
    }
    
    let id = UUID()
    let mode: Mode
    let sourceLevel: Level?
    let settings: GameSettings
    let scene: LevelEditorScene
    
    @Published private(set) var workingLevel: EditorLevelSnapshot
    @Published var currentTool: Tool = .circle
    @Published var playbackState: PlaybackState = .playing
    @Published var options = EditorOptions()
    @Published private(set) var undoStack: [EditorLevelSnapshot] = []
    @Published private(set) var redoStack: [EditorLevelSnapshot] = []
    @Published var pendingFileAction: FileMenuItem?
    @Published var isExitConfirmationPresented = false
    @Published var isResetConfirmationPresented = false
    @Published private(set) var timelineSeconds: TimeInterval = 0
    @Published var activeSelection: Selection?
    private var pendingTwoPointTool: (tool: Tool, start: Level.NormalizedPoint)?
    
    struct ButtonSettingsState {
        var buttonID: String
        var required: Bool
        var chargeSeconds: Double
        var holdSecondsEnabled: Bool
        var holdSeconds: Double
        var drainSeconds: Double
        var fillColor: String
    }
    
struct LaserSettingsState {
    var laserID: String
    var color: String
    var thickness: Double
    var sweepSeconds: Double?
    var speedDegreesPerSecond: Double?
    var initialAngleDegrees: Double?
}

    struct HitAreaSettingsState: Identifiable, Equatable {
        var id: String { hitAreaID }
        var buttonID: String
        var hitAreaID: String
        var shapeType: ShapeType
    var circleRadius: Double
    var rectWidth: Double
    var rectHeight: Double
    var rectCorner: Double
    var capsuleLength: Double
    var capsuleRadius: Double
    var polygonPoints: [Level.NormalizedPoint]
    
        enum ShapeType: String, CaseIterable, Identifiable {
            case circle
            case rectangle
            case capsule
            case polygon
            
            var id: String { rawValue }
            
            var displayName: String {
                switch self {
                case .circle: return "Circle"
                case .rectangle: return "Rectangle"
                case .capsule: return "Capsule"
                case .polygon: return "Polygon"
                }
            }
        }
    }
    
    init(level: Level?, settings: GameSettings) {
        let snapshot: EditorLevelSnapshot
        if let level {
            mode = .editing(level)
            sourceLevel = level
            snapshot = EditorLevelSnapshot(level: level)
        } else {
            mode = .creating
            sourceLevel = nil
            snapshot = EditorLevelSnapshot.blank()
        }
        workingLevel = snapshot
        self.settings = settings
        self.scene = LevelEditorScene(level: Self.makeLevel(from: snapshot), settings: settings)
        self.scene.editorDelegate = self
        scene.setPlaybackState(.playing)
        scene.timelineDidUpdate = { [weak self] seconds in
            DispatchQueue.main.async {
                self?.timelineSeconds = seconds
            }
        }
    }
    
    var headerTitle: String {
        switch mode {
        case .creating:
            return "New Level"
        case .editing(let level):
            return "Editing \(level.title)"
        }
    }
    
    var headerSubtitle: String {
        switch mode {
        case .creating:
            return "Start from a clean slate."
        case .editing(let level):
            return "Source level ID: \(level.id)"
        }
    }
    
    var canUndo: Bool {
        !undoStack.isEmpty
    }
    
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    var playbackIconName: String {
        playbackState == .playing ? "pause.circle.fill" : "play.circle.fill"
    }

    var shareURL: URL? {
        URL(string: "https://laserfingers.com/level/\(workingLevel.id)")
    }
    
    func selectTool(_ tool: Tool) {
        guard tool != currentTool else { return }
        currentTool = tool
        if tool != pendingTwoPointTool?.tool {
            pendingTwoPointTool = nil
        }
    }
    
    func togglePlayback() {
        setPlaybackState(playbackState == .playing ? .paused : .playing)
    }
    
    func resetPlayback() {
        scene.resetTimeline()
        setPlaybackState(.paused)
        timelineSeconds = 0
    }
    
    func handleFileMenuSelection(_ item: FileMenuItem) {
        switch item {
        case .exit:
            isExitConfirmationPresented = true
        case .reset:
            isResetConfirmationPresented = true
        default:
            pendingFileAction = item
        }
    }
    
    func dismissExitConfirmation() {
        isExitConfirmationPresented = false
    }
    
    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(workingLevel)
        workingLevel = previousState
        applySnapshotToScene()
    }
    
    func redo() {
        guard let restoredState = redoStack.popLast() else { return }
        undoStack.append(workingLevel)
        workingLevel = restoredState
        applySnapshotToScene()
    }
    
    func updateMetadata(id: String, title: String, description: String) {
        guard workingLevel.id != id || workingLevel.title != title || workingLevel.description != description else {
            return
        }
        pushUndoState()
        workingLevel.id = id
        workingLevel.title = title
        workingLevel.description = description
        applySnapshotToScene()
    }
    
    func setSnapEnabled(_ enabled: Bool) {
        options.snapEnabled = enabled
    }
    
    func setSnapInterval(_ value: CGFloat) {
        options.snapInterval = max(0.01, min(0.5, value))
    }
    
    func performReset() {
        pushUndoState()
        workingLevel = .blank()
        redoStack.removeAll()
        applySnapshotToScene()
        scene.resetTimeline()
        setPlaybackState(.paused)
        timelineSeconds = 0
        isResetConfirmationPresented = false
        pendingTwoPointTool = nil
    }
    
    func dismissFileAction() {
        pendingFileAction = nil
    }
    
    private func pushUndoState() {
        undoStack.append(workingLevel)
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }
    
    private func setPlaybackState(_ state: PlaybackState) {
        guard playbackState != state else { return }
        playbackState = state
        let target: LevelSceneBase.PlaybackState = (state == .playing) ? .playing : .paused
        scene.setPlaybackState(target)
    }
    
    private func applySnapshotToScene() {
        let updatedLevel = Self.makeLevel(from: workingLevel)
        scene.replaceLevelPreservingState(with: updatedLevel)
    }
    
    private func snapPoint(_ point: Level.NormalizedPoint) -> Level.NormalizedPoint {
        func snap(_ value: CGFloat) -> CGFloat {
            let clamped = value.clamped(to: -1...1)
            guard options.snapEnabled else { return clamped }
            let interval = max(options.snapInterval, 0.01)
            let snapped = (clamped / interval).rounded() * interval
            return snapped.clamped(to: -1...1)
        }
        return Level.NormalizedPoint(x: snap(point.x), y: snap(point.y))
    }
    
    private func handleTap(at point: Level.NormalizedPoint) {
        let snapped = snapPoint(point)
        switch currentTool {
        case .circle:
            addButton(at: snapped, shape: .circle(radius: 0.16))
        case .square:
            addButton(at: snapped, shape: .rectangle(width: 0.28, height: 0.28, cornerRadius: 0.02))
        case .sweeper, .segment, .rotor:
            handleTwoPointTap(for: currentTool, point: snapped)
        }
    }
    
    private func handleTwoPointTap(for tool: Tool, point: Level.NormalizedPoint) {
        if let pending = pendingTwoPointTool, pending.tool == tool {
            switch tool {
            case .sweeper:
                addSweeper(from: pending.start, to: point)
            case .segment:
                addSegment(from: pending.start, to: point)
            case .rotor:
                addRotor(center: pending.start, reference: point)
            default:
                break
            }
            pendingTwoPointTool = nil
        } else {
            pendingTwoPointTool = (tool, point)
        }
    }
    
    private func addButton(at point: Level.NormalizedPoint, shape: Level.Button.HitArea.Shape) {
        pushUndoState()
        let button = makeDefaultButton(at: point, shape: shape)
        workingLevel.buttons.append(button)
        redoStack.removeAll()
        applySnapshotToScene()
    }
    
    func hitAreas(for buttonID: String) -> [Level.Button.HitArea] {
        workingLevel.buttons.first(where: { $0.id == buttonID })?.hitAreas ?? []
    }
    
    func hitAreaSettingsState(buttonID: String, hitAreaID: String) -> HitAreaSettingsState? {
        guard let area = hitAreas(for: buttonID).first(where: { $0.id == hitAreaID }) else { return nil }
        switch area.shape {
        case .circle(let radius):
            return HitAreaSettingsState(
                buttonID: buttonID,
                hitAreaID: hitAreaID,
                shapeType: .circle,
                circleRadius: Double(radius),
                rectWidth: 0.4,
                rectHeight: 0.4,
                rectCorner: 0,
                capsuleLength: 0.5,
                capsuleRadius: 0.1,
                polygonPoints: []
            )
        case .rectangle(let width, let height, let cornerRadius):
            return HitAreaSettingsState(
                buttonID: buttonID,
                hitAreaID: hitAreaID,
                shapeType: .rectangle,
                circleRadius: 0.2,
                rectWidth: Double(width),
                rectHeight: Double(height),
                rectCorner: Double(cornerRadius ?? 0),
                capsuleLength: 0.5,
                capsuleRadius: 0.1,
                polygonPoints: []
            )
        case .capsule(let length, let radius):
            return HitAreaSettingsState(
                buttonID: buttonID,
                hitAreaID: hitAreaID,
                shapeType: .capsule,
                circleRadius: 0.2,
                rectWidth: 0.4,
                rectHeight: 0.3,
                rectCorner: 0,
                capsuleLength: Double(length),
                capsuleRadius: Double(radius),
                polygonPoints: []
            )
        case .polygon(let points):
            return HitAreaSettingsState(
                buttonID: buttonID,
                hitAreaID: hitAreaID,
                shapeType: .polygon,
                circleRadius: 0.2,
                rectWidth: 0.4,
                rectHeight: 0.3,
                rectCorner: 0,
                capsuleLength: 0.5,
                capsuleRadius: 0.1,
                polygonPoints: points
            )
        }
    }
    
    func applyHitAreaSettings(_ state: HitAreaSettingsState) {
        guard let buttonIndex = workingLevel.buttons.firstIndex(where: { $0.id == state.buttonID }),
              let areaIndex = workingLevel.buttons[buttonIndex].hitAreas.firstIndex(where: { $0.id == state.hitAreaID }) else {
            return
        }
        pushUndoState()
        var button = workingLevel.buttons[buttonIndex]
        var areas = button.hitAreas
        let shape: Level.Button.HitArea.Shape
        switch state.shapeType {
        case .circle:
            shape = .circle(radius: CGFloat(max(0.01, state.circleRadius)))
        case .rectangle:
            shape = .rectangle(
                width: CGFloat(max(0.01, state.rectWidth)),
                height: CGFloat(max(0.01, state.rectHeight)),
                cornerRadius: CGFloat(max(0, state.rectCorner))
            )
        case .capsule:
            shape = .capsule(
                length: CGFloat(max(0.01, state.capsuleLength)),
                radius: CGFloat(max(0.01, state.capsuleRadius))
            )
        case .polygon:
            shape = .polygon(points: state.polygonPoints)
        }
        let area = areas[areaIndex]
        areas[areaIndex] = Level.Button.HitArea(
            id: area.id,
            shape: shape,
            offset: area.offset,
            rotationDegrees: area.rotationDegrees
        )
        button = Level.Button(
            id: button.id,
            position: button.position,
            timing: button.timing,
            hitLogic: button.hitLogic,
            required: button.required,
            color: button.color,
            hitAreas: areas,
            effects: button.effects
        )
        workingLevel.buttons[buttonIndex] = button
        redoStack.removeAll()
        applySnapshotToScene()
    }
    
    func deleteHitArea(buttonID: String, hitAreaID: String) {
        guard let buttonIndex = workingLevel.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
        pushUndoState()
        var button = workingLevel.buttons[buttonIndex]
        var areas = button.hitAreas
        areas.removeAll { $0.id == hitAreaID }
        if areas.isEmpty {
            workingLevel.buttons.remove(at: buttonIndex)
        } else {
            button = Level.Button(
                id: button.id,
                position: button.position,
                timing: button.timing,
                hitLogic: button.hitLogic,
                required: button.required,
                color: button.color,
                hitAreas: areas,
                effects: button.effects
            )
            workingLevel.buttons[buttonIndex] = button
        }
        redoStack.removeAll()
        applySnapshotToScene()
    }
    
    private func addSweeper(from start: Level.NormalizedPoint, to end: Level.NormalizedPoint) {
        guard !pointsAreTooClose(start, end) else { return }
        let sweeper = Level.Laser.Sweeper(start: start, end: end, sweepSeconds: 3.5)
        let laser = Level.Laser(
            id: UUID().uuidString,
            color: "FFB703",
            thickness: 0.018,
            cadence: nil,
            kind: .sweeper(sweeper)
        )
        appendLaser(laser)
    }
    
    private func addSegment(from start: Level.NormalizedPoint, to end: Level.NormalizedPoint) {
        guard !pointsAreTooClose(start, end) else { return }
        let segment = Level.Laser.Segment(start: start, end: end)
        let laser = Level.Laser(
            id: UUID().uuidString,
            color: "8ECAE6",
            thickness: 0.015,
            cadence: nil,
            kind: .segment(segment)
        )
        appendLaser(laser)
    }
    
    private func addRotor(center: Level.NormalizedPoint, reference: Level.NormalizedPoint) {
        guard !pointsAreTooClose(center, reference) else { return }
        let angleRadians = atan2(reference.y - center.y, reference.x - center.x)
        let rotor = Level.Laser.Rotor(
            center: center,
            speedDegreesPerSecond: 90,
            initialAngleDegrees: angleRadians * 180 / .pi
        )
        let laser = Level.Laser(
            id: UUID().uuidString,
            color: "F72585",
            thickness: 0.012,
            cadence: nil,
            kind: .rotor(rotor)
        )
        appendLaser(laser)
    }
    
    private func appendLaser(_ laser: Level.Laser) {
        pushUndoState()
        workingLevel.lasers.append(laser)
        redoStack.removeAll()
        applySnapshotToScene()
    }

    private static func makeLevel(from snapshot: EditorLevelSnapshot) -> Level {
        let backgroundImage: String?
        switch snapshot.background {
        case .gradient:
            backgroundImage = nil
        case .asset(let name):
            backgroundImage = name
        }
        return Level(
            id: snapshot.id,
            title: snapshot.title,
            description: snapshot.description,
            maxTouches: nil,
            lives: nil,
            devices: nil,
            buttons: snapshot.buttons,
            lasers: snapshot.lasers,
            unlocks: nil,
            backgroundImage: backgroundImage,
            uuid: snapshot.uuid,
            directory: nil
        )
    }
    
    private func makeDefaultButton(at point: Level.NormalizedPoint, shape: Level.Button.HitArea.Shape) -> Level.Button {
        let buttonID = UUID().uuidString
        let areaID = "\(buttonID)-area"
        let timing = Level.Button.Timing(chargeSeconds: 1.5, holdSeconds: 0.8, drainSeconds: 1.2)
        let color = Level.Button.ColorSpec(fill: "FF4D6D", glow: "FF87AB", rim: "FFFFFF")
        let hitArea = Level.Button.HitArea(
            id: areaID,
            shape: shape,
            offset: Level.NormalizedPoint(x: 0, y: 0),
            rotationDegrees: nil
        )
        return Level.Button(
            id: buttonID,
            position: point,
            timing: timing,
            hitLogic: .any,
            required: true,
            color: color,
            hitAreas: [hitArea],
            effects: []
        )
    }
    
    private func pointsAreTooClose(_ a: Level.NormalizedPoint, _ b: Level.NormalizedPoint) -> Bool {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy) < 0.0025
    }
    
    func buttonSettingsState(for selection: Selection) -> ButtonSettingsState? {
        guard case .button(let buttonID, _) = selection,
              let buttonIndex = workingLevel.buttons.firstIndex(where: { $0.id == buttonID }) else {
            return nil
        }
        let button = workingLevel.buttons[buttonIndex]
        return ButtonSettingsState(
            buttonID: button.id,
            required: button.required,
            chargeSeconds: Double(button.timing.chargeSeconds),
            holdSecondsEnabled: button.timing.holdSeconds != nil,
            holdSeconds: Double(button.timing.holdSeconds ?? 0),
            drainSeconds: Double(button.timing.drainSeconds),
            fillColor: button.color.fill
        )
    }
    
    func applyButtonSettings(_ state: ButtonSettingsState, for selection: Selection) {
        guard case .button(let buttonID, let originalHitAreaID) = selection,
              let index = workingLevel.buttons.firstIndex(where: { $0.id == buttonID }) else {
            return
        }
        pushUndoState()
        var button = workingLevel.buttons[index]
        let timing = Level.Button.Timing(
            chargeSeconds: CGFloat(max(0, state.chargeSeconds)),
            holdSeconds: state.holdSecondsEnabled ? CGFloat(max(0, state.holdSeconds)) : nil,
            drainSeconds: CGFloat(max(0, state.drainSeconds))
        )
        let color = Level.Button.ColorSpec(
            fill: state.fillColor,
            glow: button.color.glow,
            rim: button.color.rim
        )
        let hitAreas = button.hitAreas
        let updatedButton = Level.Button(
            id: state.buttonID,
            position: button.position,
            timing: timing,
            hitLogic: button.hitLogic,
            required: state.required,
            color: color,
            hitAreas: hitAreas,
            effects: button.effects
        )
        workingLevel.buttons[index] = updatedButton
        redoStack.removeAll()
        applySnapshotToScene()
    }
    
    func laserSettingsState(for selection: Selection) -> LaserSettingsState? {
        guard case .laser(let laserID) = selection,
              let laser = workingLevel.lasers.first(where: { $0.id == laserID }) else {
            return nil
        }
        var sweep: Double?
        var speed: Double?
        var angle: Double?
        switch laser.kind {
        case .sweeper(let sweeper):
            sweep = Double(sweeper.sweepSeconds)
        case .rotor(let rotor):
            speed = Double(rotor.speedDegreesPerSecond)
            angle = Double(rotor.initialAngleDegrees)
        case .segment:
            break
        }
        return LaserSettingsState(
            laserID: laser.id,
            color: laser.color,
            thickness: Double(laser.thickness),
            sweepSeconds: sweep,
            speedDegreesPerSecond: speed,
            initialAngleDegrees: angle
        )
    }
    
    func applyLaserSettings(_ state: LaserSettingsState, for selection: Selection) {
        guard case .laser(let originalID) = selection,
              let index = workingLevel.lasers.firstIndex(where: { $0.id == originalID }) else {
            return
        }
        pushUndoState()
        let laser = workingLevel.lasers[index]
        let thickness = CGFloat(max(0.001, state.thickness))
        let updatedKind: Level.Laser.Kind
        switch laser.kind {
        case .sweeper(let sweeper):
            let sweepSeconds = CGFloat(max(0.1, state.sweepSeconds ?? Double(sweeper.sweepSeconds)))
            let updated = Level.Laser.Sweeper(start: sweeper.start, end: sweeper.end, sweepSeconds: sweepSeconds)
            updatedKind = .sweeper(updated)
        case .rotor(let rotor):
            let speed = CGFloat(state.speedDegreesPerSecond ?? Double(rotor.speedDegreesPerSecond))
            let angle = CGFloat(state.initialAngleDegrees ?? Double(rotor.initialAngleDegrees))
            let updated = Level.Laser.Rotor(
                center: rotor.center,
                speedDegreesPerSecond: speed,
                initialAngleDegrees: angle
            )
            updatedKind = .rotor(updated)
        case .segment(let segment):
            updatedKind = .segment(segment)
        }
        let updatedLaser = Level.Laser(
            id: state.laserID,
            color: state.color,
            thickness: thickness,
            cadence: laser.cadence,
            kind: updatedKind
        )
        workingLevel.lasers[index] = updatedLaser
        redoStack.removeAll()
        applySnapshotToScene()
    }
    
    func delete(selection: Selection) {
        switch selection {
        case .button(let buttonID, let hitAreaID):
            if let hitAreaID {
                deleteHitArea(buttonID: buttonID, hitAreaID: hitAreaID)
            } else {
                guard let index = workingLevel.buttons.firstIndex(where: { $0.id == buttonID }) else { return }
                pushUndoState()
                workingLevel.buttons.remove(at: index)
            }
        case .laser(let laserID):
            guard let index = workingLevel.lasers.firstIndex(where: { $0.id == laserID }) else { return }
            pushUndoState()
            workingLevel.lasers.remove(at: index)
        }
        redoStack.removeAll()
        applySnapshotToScene()
        activeSelection = nil
    }
}

extension LevelEditorViewModel: LevelEditorSceneDelegate {
    func editorScene(_ scene: LevelEditorScene, didTapNormalized point: Level.NormalizedPoint) {
        handleTap(at: point)
    }
    
    func editorScene(_ scene: LevelEditorScene, didSelectButtonID buttonID: String, hitAreaID: String?) {
        guard playbackState == .paused else { return }
        activeSelection = .button(buttonID: buttonID, hitAreaID: hitAreaID)
    }
    
    func editorScene(_ scene: LevelEditorScene, didSelectLaserID laserID: String) {
        guard playbackState == .paused else { return }
        activeSelection = .laser(laserID: laserID)
    }
}
