import SwiftUI
import SpriteKit

struct LevelEditorView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @ObservedObject var viewModel: LevelEditorViewModel
    
    var body: some View {
        ZStack(alignment: .top) {
            SpriteView(scene: viewModel.scene)
                .id(ObjectIdentifier(viewModel.scene))
                .ignoresSafeArea()
            toolbar
                .padding(.horizontal, 20)
                .padding(.top, 32)
        }
        .sheet(item: $viewModel.pendingFileAction, onDismiss: viewModel.dismissFileAction) { action in
            switch action {
            case .settings:
                LevelSettingsSheet(viewModel: viewModel)
            case .options:
                EditorOptionsSheet(viewModel: viewModel)
            case .share:
                LevelShareSheet(url: viewModel.shareURL)
            default:
                EmptyView()
            }
        }
        .sheet(item: $viewModel.activeSelection) { selection in
            ObjectSettingsSheet(viewModel: viewModel, selection: selection)
        }
        .confirmationDialog("Reset Level?", isPresented: $viewModel.isResetConfirmationPresented, titleVisibility: .visible) {
            Button("Clear Level", role: .destructive, action: viewModel.performReset)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Exit Level Editor?", isPresented: $viewModel.isExitConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                viewModel.dismissExitConfirmation()
            }
            Button("Exit", role: .destructive) {
                viewModel.dismissExitConfirmation()
                coordinator.exitLevelEditor()
            }
        } message: {
            Text("Unsaved changes will be lost.")
        }
    }
    
    private var toolbar: some View {
        HStack {
            Spacer()
            toolPicker
            Spacer()
            undoButton
            Spacer()
            redoButton
            Spacer()
            playbackButton
            Spacer()
            fileButton
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(Capsule())
    }
    
    private var toolPicker: some View {
        Menu {
            ForEach(LevelEditorViewModel.Tool.allCases) { tool in
                Button {
                    viewModel.selectTool(tool)
                } label: {
                    Label(tool.displayName, systemImage: tool.iconName)
                }
            }
        } label: {
            EditorIconButton(
                systemName: viewModel.currentTool.iconName,
                isHighlighted: true
            )
            .accessibilityLabel("Tools")
        }
    }
    
    private var undoButton: some View {
        Button(action: viewModel.undo) {
            EditorIconButton(
                systemName: "arrow.uturn.backward.circle",
                isHighlighted: false,
                isDisabled: !viewModel.canUndo
            )
        }
        .disabled(!viewModel.canUndo)
        .accessibilityLabel("Undo")
    }
    
    private var redoButton: some View {
        Button(action: viewModel.redo) {
            EditorIconButton(
                systemName: "arrow.uturn.forward.circle",
                isHighlighted: false,
                isDisabled: !viewModel.canRedo
            )
        }
        .disabled(!viewModel.canRedo)
        .accessibilityLabel("Redo")
    }
    
    private var playbackButton: some View {
        Button(action: viewModel.togglePlayback) {
            EditorIconButton(
                systemName: viewModel.playbackIconName,
                isHighlighted: viewModel.playbackState == .playing
            )
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.7)
                .onEnded { _ in
                    viewModel.resetPlayback()
                }
        )
        .accessibilityLabel(viewModel.playbackState == .playing ? "Pause" : "Play")
    }
    
    private var fileButton: some View {
        Menu {
            ForEach(LevelEditorViewModel.FileMenuItem.allCases) { item in
                Button(
                    role: item.isDestructive ? .destructive : nil,
                    action: { viewModel.handleFileMenuSelection(item) }
                ) {
                    Label(item.label, systemImage: item.iconName)
                }
            }
        } label: {
            EditorIconButton(systemName: "ellipsis.circle", isHighlighted: false)
                .accessibilityLabel("File")
        }
    }
}

private struct EditorIconButton: View {
    let systemName: String
    var isHighlighted: Bool
    var isDisabled: Bool = false
    
    var body: some View {
        Image(systemName: systemName)
            .font(.title2.weight(.semibold))
            .foregroundColor(iconColor)
            .frame(width: 46, height: 46)
            .background(background)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHighlighted ? 0.7 : 0.25), lineWidth: 1)
            )
            .opacity(isDisabled ? 0.4 : 1)
    }
    
    private var iconColor: Color {
        isDisabled ? Color.white.opacity(0.4) : .white
    }
    
    private var background: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        isHighlighted ? Color.pink.opacity(0.9) : Color.white.opacity(0.12),
                        isHighlighted ? Color.purple.opacity(0.7) : Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private struct LevelSettingsSheet: View {
    @ObservedObject var viewModel: LevelEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var levelID: String
    @State private var title: String
    @State private var description: String
    
    init(viewModel: LevelEditorViewModel) {
        self.viewModel = viewModel
        let snapshot = viewModel.workingLevel
        _levelID = State(initialValue: snapshot.id)
        _title = State(initialValue: snapshot.title)
        _description = State(initialValue: snapshot.description)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Identifiers") {
                    TextField("Level ID", text: $levelID)
                    TextField("Title", text: $title)
                }
                Section("Description") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle("Level Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.updateMetadata(id: levelID, title: title, description: description)
                        dismiss()
                    }
                    .disabled(levelID.isEmpty || title.isEmpty)
                }
            }
        }
    }
}

private struct EditorOptionsSheet: View {
    @ObservedObject var viewModel: LevelEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var snapIntervalString: String
    
    init(viewModel: LevelEditorViewModel) {
        self.viewModel = viewModel
        _snapIntervalString = State(initialValue: Self.formatInterval(viewModel.options.snapInterval))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Snapping") {
                    HStack {
                        Text("Interval")
                        Spacer()
                        Stepper(value: Binding(
                            get: { viewModel.options.snapInterval },
                            set: { updateSnapInterval($0) }
                        ), in: 0.01...0.5, step: 0.01) {
                            EmptyView()
                        }
                        .labelsHidden()
                        TextField(
                            "0.10",
                            text: Binding(
                                get: { snapIntervalString },
                                set: { updateSnapInterval(from: $0) }
                            )
                        )
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                        Toggle("Snap enabled", isOn: Binding(
                            get: { viewModel.options.snapEnabled },
                            set: { viewModel.setSnapEnabled($0) }
                        ))
                    }
                }
            }
            .navigationTitle("Editor Options")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func updateSnapInterval(_ value: CGFloat) {
        let clamped = max(0.01, min(0.5, value))
        snapIntervalString = Self.formatInterval(clamped)
        viewModel.setSnapInterval(clamped)
    }
    
    private func updateSnapInterval(from text: String) {
        snapIntervalString = text
        if let value = Double(text) {
            updateSnapInterval(CGFloat(value))
        }
    }
    
    private static func formatInterval(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}

private struct LevelShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let url {
                    ShareLink(item: url) {
                        Label("Share Level", systemImage: "square.and.arrow.up")
                            .font(.headline)
                    }
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No shareable data yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .navigationTitle("Share")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ObjectSettingsSheet: View {
    @ObservedObject var viewModel: LevelEditorViewModel
    let selection: LevelEditorViewModel.Selection
    @Environment(\.dismiss) private var dismiss
    @State private var buttonState: LevelEditorViewModel.ButtonSettingsState?
    @State private var laserState: LevelEditorViewModel.LaserSettingsState?
    @State private var path: [Destination]
    
    private enum Destination: Hashable {
        case hitArea(buttonID: String, hitAreaID: String)
    }
    
    init(viewModel: LevelEditorViewModel, selection: LevelEditorViewModel.Selection) {
        self.viewModel = viewModel
        self.selection = selection
        switch selection {
        case .button(let buttonID, let hitAreaID):
            _buttonState = State(initialValue: viewModel.buttonSettingsState(for: selection))
            _laserState = State(initialValue: nil)
            if let hitAreaID {
                _path = State(initialValue: [.hitArea(buttonID: buttonID, hitAreaID: hitAreaID)])
            } else {
                _path = State(initialValue: [])
            }
        case .laser:
            _laserState = State(initialValue: viewModel.laserSettingsState(for: selection))
            _buttonState = State(initialValue: nil)
            _path = State(initialValue: [])
        }
    }
    
    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveChanges()
                            dismiss()
                        }
                        .disabled(!canSave)
                    }
                }
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .hitArea(let buttonID, let hitAreaID):
                        HitAreaSettingsView(
                            viewModel: viewModel,
                            buttonID: buttonID,
                            hitAreaID: hitAreaID
                        )
                    }
                }
        }
        .onDisappear {
            viewModel.activeSelection = nil
        }
    }
    
    private var title: String {
        switch selection {
        case .button(_, let hitAreaID):
            return hitAreaID == nil ? "Button Settings" : "Hit Area Settings"
        case .laser:
            return "Laser Settings"
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if var buttonState = buttonState {
            let binding = Binding(
                get: { self.buttonState ?? buttonState },
                set: { self.buttonState = $0 }
            )
            buttonForm(binding)
        } else if var laserState = laserState {
            let binding = Binding(
                get: { self.laserState ?? laserState },
                set: { self.laserState = $0 }
            )
            laserForm(binding)
        } else {
            VStack(spacing: 16) {
                Text("Object no longer exists.")
                Button("Close") { dismiss() }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func buttonForm(_ state: Binding<LevelEditorViewModel.ButtonSettingsState>) -> some View {
        Form {
            Section("Button") {
                TextField("Identifier", text: state.buttonID)
                TextField("Fill Color (hex)", text: state.fillColor)
                Toggle("Required", isOn: state.required)
            }
            Section("Timing") {
                TextField("Charge Seconds", value: state.chargeSeconds, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                Toggle("Hold Enabled", isOn: state.holdSecondsEnabled)
                if state.holdSecondsEnabled.wrappedValue {
                    TextField("Hold Seconds", value: state.holdSeconds, format: .number.precision(.fractionLength(2)))
                        .keyboardType(.decimalPad)
                }
                TextField("Drain Seconds", value: state.drainSeconds, format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
            }
            Section("Hit Areas") {
                let areas = viewModel.hitAreas(for: state.buttonID.wrappedValue)
                if areas.isEmpty {
                    Text("No hit areas defined.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(areas, id: \.id) { area in
                        NavigationLink(value: Destination.hitArea(buttonID: state.buttonID.wrappedValue, hitAreaID: area.id)) {
                            VStack(alignment: .leading) {
                                Text(area.id)
                                Text(hitAreaDescription(for: area))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    viewModel.delete(selection: selection)
                    dismiss()
                } label: {
                    Text("Delete Button")
                }
            }
        }
    }
    
    @ViewBuilder
    private func laserForm(_ state: Binding<LevelEditorViewModel.LaserSettingsState>) -> some View {
        Form {
            Section("Laser") {
                TextField("Identifier", text: state.laserID)
                TextField("Color (hex)", text: state.color)
                TextField("Thickness", value: state.thickness, format: .number.precision(.fractionLength(3)))
                    .keyboardType(.decimalPad)
            }
            if state.sweepSeconds.wrappedValue != nil {
                Section("Sweeper") {
                    TextField("Sweep Seconds", value: Binding(
                        get: { state.sweepSeconds.wrappedValue ?? 0 },
                        set: { state.sweepSeconds.wrappedValue = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                }
            }
            if state.speedDegreesPerSecond.wrappedValue != nil || state.initialAngleDegrees.wrappedValue != nil {
                Section("Rotor") {
                    if state.speedDegreesPerSecond.wrappedValue != nil {
                        TextField("Speed (deg/s)", value: Binding(
                            get: { state.speedDegreesPerSecond.wrappedValue ?? 0 },
                            set: { state.speedDegreesPerSecond.wrappedValue = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                    }
                    if state.initialAngleDegrees.wrappedValue != nil {
                        TextField("Initial Angle", value: Binding(
                            get: { state.initialAngleDegrees.wrappedValue ?? 0 },
                            set: { state.initialAngleDegrees.wrappedValue = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    viewModel.delete(selection: selection)
                    dismiss()
                } label: {
                    Text("Delete Laser")
                }
            }
        }
    }
    
    private var canSave: Bool {
        switch selection {
        case .button:
            return buttonState != nil
        case .laser:
            return laserState != nil
        }
    }
    
    private func saveChanges() {
        if let buttonState {
            viewModel.applyButtonSettings(buttonState, for: selection)
        } else if let laserState {
            viewModel.applyLaserSettings(laserState, for: selection)
        }
        viewModel.activeSelection = nil
    }
    
    private func hitAreaDescription(for selection: LevelEditorViewModel.Selection) -> String {
        guard case .button(let buttonID, let hitAreaID) = selection,
              let button = viewModel.workingLevel.buttons.first(where: { $0.id == buttonID }),
              let areaID = hitAreaID,
              let area = button.hitAreas.first(where: { $0.id == areaID }) else {
            return ""
        }
        return hitAreaDescription(for: area)
    }
    
    private func hitAreaDescription(for area: Level.Button.HitArea) -> String {
        switch area.shape {
        case .circle(let radius):
            return "Circle radius \(String(format: "%.2f", radius))"
        case .rectangle(let width, let height, _):
            return "Rectangle \(String(format: "%.2f", width)) × \(String(format: "%.2f", height))"
        case .capsule(let length, let radius):
            return "Capsule length \(String(format: "%.2f", length)), radius \(String(format: "%.2f", radius))"
        case .polygon(let points):
            return "Polygon with \(points.count) points"
        }
    }
}

private struct HitAreaSettingsView: View {
    @ObservedObject var viewModel: LevelEditorViewModel
    let buttonID: String
    let hitAreaID: String
    @Environment(\.dismiss) private var dismiss
    @State private var state: LevelEditorViewModel.HitAreaSettingsState?
    
    init(viewModel: LevelEditorViewModel, buttonID: String, hitAreaID: String) {
        self.viewModel = viewModel
        self.buttonID = buttonID
        self.hitAreaID = hitAreaID
        _state = State(initialValue: viewModel.hitAreaSettingsState(buttonID: buttonID, hitAreaID: hitAreaID))
    }
    
    var body: some View {
        Form {
            if let binding = binding {
                Section("Hit Area") {
                    TextField("Identifier", text: binding.hitAreaID)
                }
                Section("Shape") {
                    Picker("Type", selection: binding.shapeType) {
                        ForEach(LevelEditorViewModel.HitAreaSettingsState.ShapeType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: binding.shapeType.wrappedValue) { newValue in
                        updateShapeDefaults(to: newValue)
                    }
                    shapeInputs(for: binding.shapeType.wrappedValue, binding: binding)
                }
                Section {
                    Button(role: .destructive) {
                        viewModel.deleteHitArea(buttonID: buttonID, hitAreaID: hitAreaID)
                        dismiss()
                    } label: {
                        Text("Delete Hit Area")
                    }
                }
            } else {
                Text("This hit area no longer exists.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(state?.hitAreaID ?? hitAreaID)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if let currentState = state {
                        viewModel.applyHitAreaSettings(currentState)
                    }
                    dismiss()
                }
                .disabled(state == nil)
            }
        }
    }
    
    private var binding: Binding<LevelEditorViewModel.HitAreaSettingsState>? {
        guard state != nil else { return nil }
        return Binding(
            get: { self.state ?? defaultState() },
            set: { self.state = $0 }
        )
    }
    
    private func defaultState() -> LevelEditorViewModel.HitAreaSettingsState {
        LevelEditorViewModel.HitAreaSettingsState(
            buttonID: buttonID,
            hitAreaID: hitAreaID,
            shapeType: .circle,
            circleRadius: 0.2,
            rectWidth: 0.4,
            rectHeight: 0.3,
            rectCorner: 0,
            capsuleLength: 0.6,
            capsuleRadius: 0.1,
            polygonPoints: defaultPolygonPoints()
        )
    }
    
    private func updateShapeDefaults(to type: LevelEditorViewModel.HitAreaSettingsState.ShapeType) {
        guard var current = state else { return }
        current.shapeType = type
        switch type {
        case .circle:
            if current.circleRadius <= 0 { current.circleRadius = 0.2 }
        case .rectangle:
            if current.rectWidth <= 0 { current.rectWidth = 0.4 }
            if current.rectHeight <= 0 { current.rectHeight = 0.3 }
        case .capsule:
            if current.capsuleLength <= 0 { current.capsuleLength = 0.6 }
            if current.capsuleRadius <= 0 { current.capsuleRadius = 0.1 }
        case .polygon:
            if current.polygonPoints.isEmpty { current.polygonPoints = defaultPolygonPoints() }
        }
        state = current
    }
    
    private func defaultPolygonPoints() -> [Level.NormalizedPoint] {
        [
            .init(x: -0.2, y: -0.2),
            .init(x: 0.2, y: -0.2),
            .init(x: 0.2, y: 0.2),
            .init(x: -0.2, y: 0.2)
        ]
    }
    @ViewBuilder
    private func shapeInputs(for type: LevelEditorViewModel.HitAreaSettingsState.ShapeType, binding: Binding<LevelEditorViewModel.HitAreaSettingsState>) -> some View {
        switch type {
        case .circle:
            TextField("Radius", value: binding.circleRadius, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
        case .rectangle:
            TextField("Width", value: binding.rectWidth, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
            TextField("Height", value: binding.rectHeight, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
            TextField("Corner Radius", value: binding.rectCorner, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
        case .capsule:
            TextField("Length", value: binding.capsuleLength, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
            TextField("Radius", value: binding.capsuleRadius, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
        case .polygon:
            Text("Polygon editing not yet available.")
                .foregroundStyle(.secondary)
        }
    }
}
