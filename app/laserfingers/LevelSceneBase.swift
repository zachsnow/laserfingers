import Foundation
import SpriteKit

enum LightingMask {
    static let button: UInt32 = 1 << 0
    static let laser: UInt32 = 1 << 1
}

class LevelSceneBase: SKScene {
    enum PlaybackState {
        case playing
        case paused
    }
    
    enum ButtonEvent {
        case touchBegan(Level.Button)
        case touchEnded(Level.Button)
        case turnedOn(Level.Button)
        case turnedOff(Level.Button)
    }
    
    private(set) var settings: GameSettings
    private(set) var level: Level
    private(set) var playbackState: PlaybackState = .paused
    private var lastUpdateTime: TimeInterval = 0
    private(set) var timelineSeconds: TimeInterval = 0 {
        didSet {
            timelineDidUpdate?(timelineSeconds)
        }
    }
    var timelineDidUpdate: ((TimeInterval) -> Void)?
    
    internal var buttonStates: [ButtonRuntime] = []
    internal var laserStates: [LaserRuntime] = []
    internal var laserIndexById: [String: Int] = [:]
    internal private(set) var fillPercentage: CGFloat = 0
    
    private let backgroundImageNode: SKSpriteNode = {
        let node = SKSpriteNode()
        node.zPosition = -120
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.lightingBitMask = LightingMask.laser
        node.blendMode = .replace
        node.name = "GameplayBackgroundImage"
        return node
    }()
    
    private let ambientLightNode: SKLightNode = {
        let node = SKLightNode()
        node.categoryBitMask = LightingMask.laser
        node.falloff = 0
        node.lightColor = SKColor(white: 1, alpha: 0.18)
        node.ambientColor = SKColor(white: 0.2, alpha: 0.25)
        node.isEnabled = true
        node.zPosition = -110
        return node
    }()
    
    init(level: Level, settings: GameSettings) {
        self.level = level
        self.settings = settings
        super.init(size: CGSize(width: 1920, height: 1080))
        scaleMode = .resizeFill
        backgroundColor = .black
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateLevel(_ newLevel: Level) {
        level = newLevel
        rebuildScene()
    }
    
    func replaceLevelPreservingState(with newLevel: Level) {
        guard let transform = currentLayoutTransform() else {
            updateLevel(newLevel)
            return
        }
        let oldButtonMap = Dictionary(uniqueKeysWithValues: buttonStates.map { ($0.spec.id, $0) })
        let oldLaserMap = Dictionary(uniqueKeysWithValues: laserStates.map { ($0.spec.id, $0) })
        let newButtonIDs = Set(newLevel.buttons.map { $0.id })
        let newLaserIDs = Set(newLevel.lasers.map { $0.id })
        
        // Remove buttons that no longer exist
        for runtime in buttonStates where !newButtonIDs.contains(runtime.spec.id) {
            runtime.node.removeFromParent()
        }
        // Remove lasers that no longer exist
        for runtime in laserStates where !newLaserIDs.contains(runtime.spec.id) {
            runtime.node.removeFromParent()
        }
        
        var updatedButtons: [ButtonRuntime] = []
        for button in newLevel.buttons {
            if let runtime = oldButtonMap[button.id], runtime.spec == button {
                updatedButtons.append(runtime)
            } else {
                let node = ButtonNode(button: button, transform: transform)
                node.zPosition = 5
                addChild(node)
                updatedButtons.append(ButtonRuntime(spec: button, node: node))
            }
        }
        buttonStates = updatedButtons
        
        var updatedLasers: [LaserRuntime] = []
        for laser in newLevel.lasers {
            if let runtime = oldLaserMap[laser.id], runtime.spec == laser {
                updatedLasers.append(runtime)
            } else if var newRuntime = makeLaserRuntime(from: laser, transform: transform) {
                newRuntime.node.startMotion()
                newRuntime.applyFiringState(immediate: true)
                newRuntime.node.zPosition = 10
                addChild(newRuntime.node)
                updatedLasers.append(newRuntime)
            }
        }
        laserStates = updatedLasers
        laserIndexById = Dictionary(uniqueKeysWithValues: laserStates.enumerated().map { ($0.element.spec.id, $0.offset) })
        level = newLevel
    }
    
    func applyVisualSettings(_ newSettings: GameSettings) {
        settings = newSettings
        for index in laserStates.indices {
            laserStates[index].node.configureVisualEffects(
                glowEnabled: newSettings.glowEnabled,
                blurEnabled: newSettings.blurEnabled,
                afterimageEnabled: newSettings.afterimageEnabled
            )
        }
    }
    
    func setPlaybackState(_ state: PlaybackState) {
        guard playbackState != state else { return }
        playbackState = state
        if state == .paused {
            lastUpdateTime = 0
        }
    }
    
    func resetTimeline() {
        timelineSeconds = 0
        lastUpdateTime = 0
        addButtons()
        spawnLasers()
    }
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        view.isMultipleTouchEnabled = true
        if buttonStates.isEmpty {
            rebuildScene()
        }
        isUserInteractionEnabled = true
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateBackgroundImageLayout()
        updateAmbientLightLayout()
        layoutScene()
    }
    
    override func update(_ currentTime: TimeInterval) {
        guard playbackState == .playing else {
            lastUpdateTime = currentTime
            return
        }
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = min(currentTime - lastUpdateTime, 1 / 20)
        lastUpdateTime = currentTime
        timelineSeconds += delta
        advanceTimeline(delta: delta, currentTime: currentTime)
    }
    
    func advanceTimeline(delta: TimeInterval, currentTime: TimeInterval) {
        let touchPoints = activeTouchPoints()
        updateButtons(delta: delta, touchPoints: touchPoints)
        updateLasers(delta: delta)
        didAdvanceTimeline(delta: delta, currentTime: currentTime)
    }
    
    func didAdvanceTimeline(delta: TimeInterval, currentTime: TimeInterval) {
        // Subclasses can hook into the timeline loop.
    }
    
    func activeTouchPoints() -> [CGPoint] {
        []
    }
    
    func handleButtonEvent(_ event: ButtonEvent) {
        // Subclasses can override for haptics or other side-effects.
    }
    
    func didUpdateFillPercentage(_ value: CGFloat) {
        // Subclasses can override to propagate to other systems.
    }
    
    func rebuildScene() {
        backgroundImageNode.removeFromParent()
        addBackground()
        addButtons()
        spawnLasers()
    }
    
    // MARK: - Scene Construction
    
    private func addBackground() {
        if let texture = loadBackgroundTexture() {
            backgroundColor = .black
            backgroundImageNode.texture = texture
            backgroundImageNode.size = texture.size()
            addChild(backgroundImageNode)
            updateBackgroundImageLayout()
        } else {
            backgroundColor = .black
        }
        addAmbientLight()
    }
    
    private func loadBackgroundTexture() -> SKTexture? {
        guard let path = resolveBackgroundImagePath() else { return nil }
        return SKTexture(imageNamed: path)
    }
    
    private func resolveBackgroundImagePath() -> String? {
        guard let backgroundImage = level.backgroundImage,
              let directory = level.directory else { return nil }
        let fileManager = FileManager.default
        let primaryURL = URL(fileURLWithPath: backgroundImage, relativeTo: directory).standardizedFileURL
        
        if fileManager.fileExists(atPath: primaryURL.path),
           let bundleRelative = bundleRelativePath(for: primaryURL) {
            return bundleRelative
        }
        
        if !isDirectoryInsideBundle(directory),
           let sanitized = sanitizedBundleResourcePath(backgroundImage),
           let bundleRoot = Bundle.main.resourceURL?.standardizedFileURL {
            let fallbackURL = bundleRoot.appendingPathComponent(sanitized).standardizedFileURL
            if fileManager.fileExists(atPath: fallbackURL.path),
               let bundleRelative = bundleRelativePath(for: fallbackURL) {
                return bundleRelative
            }
        }
        return nil
    }
    
    private func bundleRelativePath(for url: URL) -> String? {
        guard let bundleRoot = Bundle.main.resourceURL?.standardizedFileURL else { return nil }
        let resourcePath = url.standardizedFileURL.path
        let bundlePath = bundleRoot.path
        guard resourcePath.hasPrefix(bundlePath) else { return nil }
        let startIndex = resourcePath.index(resourcePath.startIndex, offsetBy: bundlePath.count)
        let trimmed = resourcePath[startIndex...]
        let cleaned = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleaned.isEmpty ? nil : cleaned
    }
    
    private func sanitizedBundleResourcePath(_ path: String) -> String? {
        var trimmed = path
        while trimmed.hasPrefix("../") {
            trimmed.removeFirst(3)
        }
        while trimmed.hasPrefix("./") {
            trimmed.removeFirst(2)
        }
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private func isDirectoryInsideBundle(_ directory: URL) -> Bool {
        guard let bundleRoot = Bundle.main.resourceURL?.standardizedFileURL else { return false }
        let dirPath = directory.standardizedFileURL.path
        return dirPath.hasPrefix(bundleRoot.path)
    }
    
    private func updateBackgroundImageLayout() {
        guard backgroundImageNode.parent != nil else { return }
        guard size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        backgroundImageNode.position = center
        let referenceSize = backgroundImageNode.texture?.size() ?? CGSize(width: 1, height: 1)
        let scale = max(size.width / referenceSize.width, size.height / referenceSize.height)
        backgroundImageNode.size = CGSize(width: referenceSize.width * scale, height: referenceSize.height * scale)
    }
    
    private func addAmbientLight() {
        ambientLightNode.removeFromParent()
        addChild(ambientLightNode)
        updateAmbientLightLayout()
    }
    
    private func updateAmbientLightLayout() {
        guard ambientLightNode.parent != nil else { return }
        ambientLightNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }
    
    private(set) var layoutTransform: NormalizedLayoutTransform?
    
    internal func currentLayoutTransform() -> NormalizedLayoutTransform? {
        let transform = NormalizedLayoutTransform(frame: frame)
        layoutTransform = transform
        return transform
    }
    
    internal func layoutScene() {
        guard let transform = currentLayoutTransform() else { return }
        for runtime in buttonStates {
            runtime.node.updateLayout(transform: transform)
        }
        for index in laserStates.indices {
            var runtime = laserStates[index]
            runtime.updateLayout(transform: transform)
            laserStates[index] = runtime
        }
    }
    
    func normalizedPoint(from scenePoint: CGPoint) -> Level.NormalizedPoint? {
        guard let transform = layoutTransform else { return nil }
        return transform.normalizedPoint(from: scenePoint)
    }
    
    private let selectionRadius: CGFloat = 28
    
    func buttonSelection(at scenePoint: CGPoint, radius: CGFloat? = nil) -> (Level.Button, Level.Button.HitArea?)? {
        let hitRadius = radius ?? selectionRadius
        for runtime in buttonStates {
            if let area = runtime.node.hitArea(at: scenePoint, radius: hitRadius, in: self) {
                return (runtime.spec, area)
            }
        }
        return nil
    }
    
    func laserSelection(at scenePoint: CGPoint, radius: CGFloat? = nil) -> Level.Laser? {
        let hitRadius = radius ?? selectionRadius
        for runtime in laserStates {
            let polygons = runtime.node.collisionPolygons(in: self)
            if polygons.contains(where: { $0.contains(point: scenePoint, radius: hitRadius) }) {
                return runtime.spec
            }
        }
        return nil
    }
    
    private func addButtons() {
        buttonStates.forEach { $0.node.removeFromParent() }
        buttonStates.removeAll()
        
        guard
            !level.buttons.isEmpty,
            let transform = currentLayoutTransform()
        else { return }
        
        for button in level.buttons {
            let node = ButtonNode(button: button, transform: transform)
            node.zPosition = 5
            addChild(node)
            buttonStates.append(ButtonRuntime(spec: button, node: node))
        }
    }
    
    private func spawnLasers() {
        laserStates.forEach { $0.node.removeFromParent() }
        laserStates.removeAll()
        laserIndexById.removeAll()
        
        guard let transform = currentLayoutTransform() else { return }
        
        for spec in level.lasers {
            guard var runtime = makeLaserRuntime(from: spec, transform: transform) else { continue }
            runtime.node.startMotion()
            runtime.applyFiringState(immediate: true)
            runtime.node.zPosition = 10
            addChild(runtime.node)
            laserIndexById[spec.id] = laserStates.count
            laserStates.append(runtime)
        }
    }
    
    private func makeLaserRuntime(from spec: Level.Laser, transform: NormalizedLayoutTransform) -> LaserRuntime? {
        let color = SKColor.fromHex(spec.color, alpha: 0.95)
        let thickness = max(spec.thickness, 0.005)
        let node: LaserNode
        switch spec.kind {
        case .sweeper(let sweeper):
            node = SweepingLaserNode(spec: sweeper, thicknessScale: thickness, color: color)
        case .rotor(let rotor):
            node = RotatingLaserNode(spec: rotor, thicknessScale: thickness, color: color)
        case .segment(let segment):
            node = SegmentLaserNode(spec: segment, thicknessScale: thickness, color: color)
        }
        node.alpha = 0
        node.run(SKAction.fadeIn(withDuration: 0.2))
        node.addLight()
        node.configureVisualEffects(
            glowEnabled: settings.glowEnabled,
            blurEnabled: settings.blurEnabled,
            afterimageEnabled: settings.afterimageEnabled
        )
        var runtime = LaserRuntime(spec: spec, node: node)
        runtime.updateLayout(transform: transform)
        return runtime
    }
    
    // MARK: - Timeline Updates
    
    @discardableResult
    private func updateButtons(delta: TimeInterval, touchPoints: [CGPoint]) -> CGFloat {
        guard !buttonStates.isEmpty else {
            fillPercentage = 0
            didUpdateFillPercentage(fillPercentage)
            return fillPercentage
        }
        for index in buttonStates.indices {
            var runtime = buttonStates[index]
            let areaCounts = runtime.node.touchCounts(for: touchPoints, in: self)
            let totalTouches = areaCounts.reduce(0, +)
            let wasTouching = runtime.isTouching
            let isTouching = totalTouches > 0
            runtime.isTouching = isTouching
            runtime.node.setTouching(isTouching)
            if isTouching && !wasTouching {
                runEffects(for: runtime.spec, trigger: .touchStarted)
                handleButtonEvent(.touchBegan(runtime.spec))
            } else if !isTouching && wasTouching {
                runEffects(for: runtime.spec, trigger: .touchEnded)
                handleButtonEvent(.touchEnded(runtime.spec))
            }
            let charging: Bool
            switch runtime.spec.hitLogic {
            case .any:
                charging = totalTouches > 0
            case .all:
                charging = !areaCounts.isEmpty && areaCounts.allSatisfy { $0 > 0 }
            }
            let (turnedOn, turnedOff) = runtime.advanceCharge(delta: delta, charging: charging)
            runtime.node.updateChargeDisplay(runtime.charge)
            if turnedOn {
                runEffects(for: runtime.spec, trigger: .turnedOn)
                handleButtonEvent(.turnedOn(runtime.spec))
            }
            if turnedOff {
                runEffects(for: runtime.spec, trigger: .turnedOff)
                handleButtonEvent(.turnedOff(runtime.spec))
            }
            buttonStates[index] = runtime
        }
        let requiredButtons = buttonStates.filter { $0.spec.required }
        let trackedButtons = requiredButtons.isEmpty ? buttonStates : requiredButtons
        if trackedButtons.isEmpty {
            fillPercentage = 0
        } else {
            let total = trackedButtons.reduce(CGFloat(0)) { $0 + $1.charge }
            fillPercentage = total / CGFloat(trackedButtons.count)
        }
        didUpdateFillPercentage(fillPercentage)
        return fillPercentage
    }
    
    internal func updateLasers(delta: TimeInterval) {
        guard !laserStates.isEmpty else { return }
        for index in laserStates.indices {
            var runtime = laserStates[index]
            runtime.advance(delta: delta)
            laserStates[index] = runtime
        }
    }
    
    // MARK: - Button Effects
    
    private func runEffects(for button: Level.Button, trigger: Level.Button.Effect.Trigger) {
        guard !button.effects.isEmpty else { return }
        for effect in button.effects where effect.trigger == trigger {
            applyLaserAction(effect.action)
        }
    }
    
    private func applyLaserAction(_ action: Level.Button.Effect.Action) {
        for laserId in action.lasers {
            guard let index = laserIndexById[laserId] else { continue }
            laserStates[index].apply(action: action.kind)
        }
    }
}

// MARK: - Runtime Models

struct ButtonRuntime {
    let spec: Level.Button
    let node: ButtonNode
    var isTouching: Bool = false
    var charge: CGFloat = 0
    var holdCountdown: Double?
    var isFullyCharged: Bool = false
    
    init(spec: Level.Button, node: ButtonNode) {
        self.spec = spec
        self.node = node
    }
    
    mutating func advanceCharge(delta: TimeInterval, charging: Bool) -> (Bool, Bool) {
        var turnedOn = false
        var turnedOff = false
        let wasFull = isFullyCharged
        
        if charging {
            if spec.timing.chargeSeconds <= 0 {
                charge = 1
            } else {
                let increment = CGFloat(delta / spec.timing.chargeSeconds)
                charge = min(1, charge + increment)
            }
        } else {
            var remaining = delta
            if isFullyCharged, let hold = holdCountdown {
                if hold.isInfinite {
                    remaining = 0
                } else {
                    let consumed = min(hold, delta)
                    holdCountdown = max(hold - consumed, 0)
                    remaining = delta - consumed
                }
            }
            if remaining > 0 {
                drain(by: remaining)
            }
        }
        
        charge = charge.clamped(to: 0...1)
        if charge >= 1 {
            charge = 1
            isFullyCharged = true
            if !wasFull {
                turnedOn = true
                holdCountdown = spec.timing.holdSeconds.map { max($0, 0) } ?? Double.infinity
            }
        } else {
            if wasFull {
                turnedOff = true
            }
            isFullyCharged = false
            holdCountdown = nil
        }
        
        return (turnedOn, turnedOff)
    }
    
    mutating func reset() {
        isTouching = false
        charge = 0
        holdCountdown = nil
        isFullyCharged = false
        node.setTouching(false)
        node.updateChargeDisplay(0)
    }
    
    private mutating func drain(by delta: TimeInterval) {
        guard delta > 0 else { return }
        if spec.timing.drainSeconds <= 0 {
            charge = 0
        } else {
            let decrement = CGFloat(delta / spec.timing.drainSeconds)
            charge = max(0, charge - decrement)
        }
    }
}

final class ButtonNode: SKNode {
    private struct AreaVisual {
        let spec: Level.Button.HitArea
        let container: SKNode
        let outline: SKShapeNode
        let fill: SKShapeNode
        let glow: SKShapeNode
        var hitPath: CGPath
    }
    
    private let button: Level.Button
    private let colorSpec: Level.Button.ColorSpec
    private var areas: [AreaVisual] = []
    private let lightNode: SKLightNode
    
    init(button: Level.Button, transform: NormalizedLayoutTransform) {
        self.button = button
        self.colorSpec = button.color
        lightNode = SKLightNode()
        super.init()
        lightNode.categoryBitMask = LightingMask.button
        lightNode.falloff = 3
        lightNode.ambientColor = .clear
        lightNode.lightColor = SKColor.fromHex(button.color.fill, alpha: 0.35)
        lightNode.alpha = 0.8
        lightNode.isEnabled = true
        addChild(lightNode)
        buildAreas(from: button.hitAreas)
        updateLayout(transform: transform)
        startGlowPulse()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateLayout(transform: NormalizedLayoutTransform) {
        position = transform.point(from: button.position)
        lightNode.position = .zero
        for index in areas.indices {
            var visual = areas[index]
            let spec = visual.spec
            let path = ButtonNode.makePath(for: spec.shape, transform: transform)
            visual.outline.path = path
            visual.fill.path = path
            visual.glow.path = path
            visual.glow.xScale = 1.08
            visual.glow.yScale = 1.08
            visual.hitPath = ButtonNode.makeHitPath(from: path)
            let offsetPoint = transform.offset(from: spec.offset)
            visual.container.position = offsetPoint
            if let rotation = spec.rotationDegrees {
                visual.container.zRotation = CGFloat(rotation * .pi / 180)
            } else {
                visual.container.zRotation = 0
            }
            areas[index] = visual
        }
    }
    
    func updateChargeDisplay(_ progress: CGFloat) {
        let clamped = progress.clamped(to: 0...1)
        for index in areas.indices {
            let scale = 0.25 + 0.75 * clamped
            areas[index].fill.xScale = scale
            areas[index].fill.yScale = scale
            areas[index].fill.alpha = 0.3 + 0.6 * clamped
            areas[index].glow.alpha = 0.12 + 0.4 * clamped
        }
    }
    
    func setTouching(_ isTouching: Bool) {
        for index in areas.indices {
            let strokeAlpha: CGFloat = isTouching ? 0.95 : 0.65
            areas[index].outline.strokeColor = SKColor.fromHex(colorSpec.rim ?? colorSpec.fill, alpha: strokeAlpha)
            areas[index].fill.removeAction(forKey: "touchFade")
            let targetAlpha: CGFloat = isTouching ? 0.95 : 0.25
            let fade = SKAction.fadeAlpha(to: targetAlpha, duration: 0.08)
            areas[index].fill.run(fade, withKey: "touchFade")
            areas[index].glow.removeAction(forKey: "touchGlow")
            let glowAlpha: CGFloat = isTouching ? 0.45 : 0.2
            let glowFade = SKAction.fadeAlpha(to: glowAlpha, duration: 0.08)
            areas[index].glow.run(glowFade, withKey: "touchGlow")
        }
        let targetAlpha: CGFloat = isTouching ? 1.1 : 0.7
        lightNode.removeAction(forKey: "touchLight")
        lightNode.run(SKAction.fadeAlpha(to: targetAlpha, duration: 0.08), withKey: "touchLight")
    }
    
    func touchCounts(for points: [CGPoint], in scene: SKScene) -> [Int] {
        guard !areas.isEmpty else { return [] }
        var counts = Array(repeating: 0, count: areas.count)
        for (index, area) in areas.enumerated() {
            for point in points {
                let local = area.container.convert(point, from: scene)
                if area.hitPath.contains(local) {
                    counts[index] += 1
                }
            }
        }
        return counts
    }

    func hitArea(at scenePoint: CGPoint, radius: CGFloat, in scene: SKScene) -> Level.Button.HitArea? {
        for visual in areas {
            let local = visual.container.convert(scenePoint, from: scene)
            if visual.hitPath.contains(local) {
                return visual.spec
            }
            if radius > 0 {
                let stroked = visual.hitPath.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
                if stroked.contains(local) {
                    return visual.spec
                }
            }
        }
        return nil
    }
    
    func celebrate() {
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.08, duration: 0.15),
            SKAction.scale(to: 1.0, duration: 0.15)
        ])
        run(pulse)
    }
    
    private func buildAreas(from specs: [Level.Button.HitArea]) {
        for spec in specs {
            let outline = SKShapeNode()
            outline.fillColor = SKColor.black.withAlphaComponent(0.25)
            outline.lineWidth = 3
            outline.strokeColor = SKColor.white.withAlphaComponent(0.95)
            outline.glowWidth = 10
            
            let fill = SKShapeNode()
            fill.fillColor = SKColor.fromHex(colorSpec.fill).brightened(by: 0.2)
            fill.strokeColor = .clear
            fill.alpha = 0.45
            
            let glow = SKShapeNode()
            glow.fillColor = SKColor.white.withAlphaComponent(0.08)
            glow.strokeColor = .clear
            glow.alpha = 0.2
            glow.blendMode = .add
            
            let container = SKNode()
            container.addChild(glow)
            container.addChild(outline)
            container.addChild(fill)
            addChild(container)
            
            let basePath = CGMutablePath()
            let visual = AreaVisual(
                spec: spec,
                container: container,
                outline: outline,
                fill: fill,
                glow: glow,
                hitPath: basePath
            )
            areas.append(visual)
        }
    }
    
    private static func makePath(for shape: Level.Button.HitArea.Shape, transform: NormalizedLayoutTransform) -> CGPath {
        let path = CGMutablePath()
        switch shape {
        case .circle(let radius):
            let r = max(transform.length(from: radius), 2)
            path.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        case .rectangle(let width, let height, let cornerRadius):
            let w = max(transform.length(from: width), 4)
            let h = max(transform.length(from: height), 4)
            let corner = transform.length(from: cornerRadius ?? 0)
            path.addRoundedRect(
                in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                cornerWidth: corner,
                cornerHeight: corner
            )
        case .capsule(let length, let radius):
            let w = max(transform.length(from: length), 6)
            let h = max(transform.length(from: radius * 2) , 4)
            path.addRoundedRect(
                in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                cornerWidth: h / 2,
                cornerHeight: h / 2
            )
        case .polygon(let points):
            guard let first = points.first else { break }
            path.move(to: transform.localPoint(from: first))
            for point in points.dropFirst() {
                path.addLine(to: transform.localPoint(from: point))
            }
            path.closeSubpath()
        }
        return path.copy() ?? path
    }
    
    private static func makeHitPath(from path: CGPath) -> CGPath {
        var transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        return path.copy(using: &transform) ?? path
    }
    
    private func startGlowPulse() {
        for index in areas.indices {
            let pulseUp = SKAction.group([
                SKAction.fadeAlpha(to: 0.4, duration: 0.8),
                SKAction.scale(to: 1.15, duration: 0.8)
            ])
            let pulseDown = SKAction.group([
                SKAction.fadeAlpha(to: 0.2, duration: 0.8),
                SKAction.scale(to: 1.0, duration: 0.8)
            ])
            let sequence = SKAction.sequence([pulseUp, pulseDown])
            areas[index].glow.run(SKAction.repeatForever(sequence), withKey: "glowPulse")
        }
        lightNode.removeAction(forKey: "lightPulse")
        let lighten = SKAction.sequence([
            SKAction.fadeAlpha(to: 1.0, duration: 0.8),
            SKAction.fadeAlpha(to: 0.6, duration: 0.8)
        ])
        lightNode.run(SKAction.repeatForever(lighten), withKey: "lightPulse")
    }
}

struct LaserRuntime {
    let spec: Level.Laser
    let node: LaserNode
    private var cadence: LaserCadence?
    private var manualOverride: Bool?
    private var lastAppliedState: Bool?
    
    init(spec: Level.Laser, node: LaserNode) {
        self.spec = spec
        self.node = node
        if let steps = spec.cadence?.filter({ step in
            guard let duration = step.duration else { return true }
            return duration > 0
        }), !steps.isEmpty {
            self.cadence = LaserCadence(steps: steps)
        }
    }
    
    mutating func advance(delta: TimeInterval) {
        cadence?.advance(by: delta)
        applyFiringState(immediate: false)
    }
    
    mutating func apply(action: Level.Button.Effect.Action.Kind) {
        switch action {
        case .turnOnLasers:
            manualOverride = true
        case .turnOffLasers:
            manualOverride = false
        case .toggleLasers:
            let current = effectiveState
            manualOverride = !current
        }
        applyFiringState(immediate: true)
    }
    
    mutating func applyFiringState(immediate: Bool) {
        let state = effectiveState
        if immediate || lastAppliedState != state {
            node.setFiring(active: state)
            lastAppliedState = state
        }
    }
    
    mutating func updateLayout(transform: NormalizedLayoutTransform) {
        node.updateLayout(using: transform)
        if let lastAppliedState {
            node.setFiring(active: lastAppliedState)
        } else {
            applyFiringState(immediate: true)
        }
    }
    
    mutating func reset() {
        manualOverride = nil
        lastAppliedState = nil
        cadence?.reset()
        applyFiringState(immediate: true)
    }
    
    private var effectiveState: Bool {
        if let manualOverride {
            return manualOverride
        }
        if let cadence {
            return cadence.isOn
        }
        return true
    }
}

private struct LaserCadence {
    private let steps: [Level.Laser.CadenceStep]
    private var index: Int = 0
    private var elapsed: Double = 0
    private var locked = false
    
    init(steps: [Level.Laser.CadenceStep]) {
        self.steps = steps
        if steps.first?.duration == nil {
            locked = true
        }
    }
    
    mutating func advance(by delta: TimeInterval) {
        guard !locked, !steps.isEmpty else { return }
        elapsed += delta
        let duration = steps[index].duration ?? .infinity
        guard duration > 0 else {
            locked = true
            return
        }
        while elapsed >= duration {
            elapsed -= duration
            index = (index + 1) % steps.count
            if steps[index].duration == nil {
                locked = true
                break
            }
        }
    }
    
    mutating func reset() {
        index = 0
        elapsed = 0
        locked = steps.first?.duration == nil
    }
    
    var isOn: Bool {
        guard !steps.isEmpty else { return true }
        return steps[index].state == .on
    }
}

// MARK: - Laser Nodes

typealias LaserNode = SKNode & LaserObstacle

protocol LaserObstacle: AnyObject {
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool
    func startMotion()
    func setFiring(active: Bool)
    func updateLayout(using transform: NormalizedLayoutTransform)
    func collisionPolygons(in scene: SKScene) -> [Polygon]
    func addLight()
    func didActivateLaser()
    func didDeactivateLaser()
    func configureVisualEffects(glowEnabled: Bool, blurEnabled: Bool, afterimageEnabled: Bool)
}

extension LaserObstacle {
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool { true }
    func startMotion() {}
    func setFiring(active: Bool) {}
    func updateLayout(using transform: NormalizedLayoutTransform) {}
    func collisionPolygons(in scene: SKScene) -> [Polygon] { [] }
    func addLight() {}
    func didActivateLaser() {}
    func didDeactivateLaser() {}
    func configureVisualEffects(glowEnabled: Bool, blurEnabled: Bool, afterimageEnabled: Bool) {}
}

// NOTE: BaseLaserNode and laser subclasses remain in GameScene.swift for now.

// MARK: - Layout Transform

struct NormalizedLayoutTransform {
    let frame: CGRect
    private let shortScale: CGFloat
    private let shortAxisIsHorizontal: Bool
    
    init?(frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return nil }
        self.frame = frame
        shortAxisIsHorizontal = frame.width <= frame.height
        shortScale = min(frame.width, frame.height) / 2
    }
    
    func point(from normalized: Level.NormalizedPoint) -> CGPoint {
        convert(shortComponent: normalized.x * shortScale, longComponent: normalized.y * shortScale)
    }
    
    func offset(from normalized: Level.NormalizedPoint) -> CGPoint {
        if shortAxisIsHorizontal {
            return CGPoint(x: normalized.x * shortScale, y: normalized.y * shortScale)
        } else {
            return CGPoint(x: normalized.y * shortScale, y: normalized.x * shortScale)
        }
    }
    
    func localPoint(from normalized: Level.NormalizedPoint) -> CGPoint {
        CGPoint(x: normalized.x * shortScale, y: normalized.y * shortScale)
    }
    
    func length(from normalizedValue: CGFloat) -> CGFloat {
        abs(normalizedValue) * shortScale
    }
    
    func normalizedPoint(from scenePoint: CGPoint) -> Level.NormalizedPoint? {
        let dx = scenePoint.x - frame.midX
        let dy = scenePoint.y - frame.midY
        if shortAxisIsHorizontal {
            return Level.NormalizedPoint(x: dx / shortScale, y: dy / shortScale)
        } else {
            return Level.NormalizedPoint(x: dy / shortScale, y: dx / shortScale)
        }
    }
    
    private func convert(shortComponent: CGFloat, longComponent: CGFloat) -> CGPoint {
        if shortAxisIsHorizontal {
            return CGPoint(
                x: frame.midX + shortComponent,
                y: frame.midY + longComponent
            )
        } else {
            return CGPoint(
                x: frame.midX + longComponent,
                y: frame.midY + shortComponent
            )
        }
    }
}

// MARK: - Shared Utilities

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
    
    func interpolated(to other: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }
}

struct Polygon {
    let points: [CGPoint]
    
    var edges: [(CGPoint, CGPoint)] {
        guard points.count > 1 else { return [] }
        var result: [(CGPoint, CGPoint)] = []
        for index in points.indices {
            let next = (index + 1) % points.count
            result.append((points[index], points[next]))
        }
        return result
    }
    
    func contains(_ point: CGPoint) -> Bool {
        guard points.count >= 3 else { return false }
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let pi = points[i]
            let pj = points[j]
            let intersects = ((pi.y > point.y) != (pj.y > point.y)) &&
            (point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y + .ulpOfOne) + pi.x)
            if intersects {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
    
    func contains(point: CGPoint, radius: CGFloat) -> Bool {
        if contains(point) { return true }
        guard radius > 0 else { return false }
        let rSquared = radius * radius
        for edge in edges {
            if distancePointToSegmentSquared(point, edge.0, edge.1) <= rSquared {
                return true
            }
        }
        for vertex in points {
            let dx = vertex.x - point.x
            let dy = vertex.y - point.y
            if dx * dx + dy * dy <= rSquared {
                return true
            }
        }
        return false
    }
    
    private func distancePointToSegmentSquared(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        if a == b {
            let dx = point.x - a.x
            let dy = point.y - a.y
            return dx * dx + dy * dy
        }
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ap = CGPoint(x: point.x - a.x, y: point.y - a.y)
        let abLengthSquared = ab.x * ab.x + ab.y * ab.y
        let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / abLengthSquared))
        let projection = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        let dx = point.x - projection.x
        let dy = point.y - projection.y
        return dx * dx + dy * dy
    }
}

// MARK: - Laser Node Implementations

class BaseLaserNode: SKNode, LaserObstacle {
    let color: SKColor
    let beam = SKShapeNode()
    let glowShell = SKShapeNode()
    let bloomNode = SKEffectNode()
    let bloomShape = SKShapeNode()
    let lightNode = SKLightNode()
    private var firingState = true
    private var glowEffectsEnabled = true
    private var blurEffectsEnabled = true
    private var afterimageEffectsEnabled = true
    
    init(color: SKColor) {
        self.color = color
        super.init()
        setupNodes()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func addLight() {
        lightNode.categoryBitMask = LightingMask.laser
        lightNode.isEnabled = firingState
        addChild(lightNode)
    }
    
    func setFiring(active: Bool) {
        guard firingState != active else { return }
        firingState = active
        lightNode.isEnabled = active
        beam.isHidden = !active
        updateGlowVisibility()
        updateBlurVisibility()
        if active {
            didActivateLaser()
        } else {
            didDeactivateLaser()
        }
    }
    
    func didActivateLaser() {}
    func didDeactivateLaser() {}
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        guard firingState else { return false }
        let local = convert(scenePoint, from: scene)
        if let path = beam.path, path.contains(local) {
            return true
        }
        return false
    }
    
    func collisionPolygons(in scene: SKScene) -> [Polygon] {
        guard firingState, let path = beam.path else { return [] }
        let rect = path.boundingBoxOfPath
        let localPoints = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let worldPoints = localPoints.map { beam.convert($0, to: scene) }
        return [Polygon(points: worldPoints)]
    }
    
    func startMotion() {}
    
    func updateLayout(using transform: NormalizedLayoutTransform) {}
    
    func configureVisualEffects(glowEnabled: Bool, blurEnabled: Bool, afterimageEnabled: Bool) {
        glowEffectsEnabled = glowEnabled
        blurEffectsEnabled = blurEnabled
        afterimageEffectsEnabled = afterimageEnabled
        updateGlowVisibility()
        updateBlurVisibility()
        if !afterimageEnabled {
            removeAction(forKey: "afterimage")
        } else if firingState {
            startAfterimageLoop()
        }
    }
    
    func startAfterimageLoop() {}
    
    func updateBloomFilter(radius: CGFloat) {
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        bloomNode.filter = filter
        bloomNode.shouldCenterFilter = true
    }
    
    private func setupNodes() {
        // Glow layer (behind beam)
        glowShell.fillColor = color.withAlphaComponent(0.4)
        glowShell.strokeColor = color.withAlphaComponent(0.18)
        glowShell.lineWidth = 0
        glowShell.glowWidth = 0
        glowShell.blendMode = .add
        glowShell.zPosition = -1
        addChild(glowShell)

        // Bloom/blur layer (between glow and beam)
        bloomShape.fillColor = color.withAlphaComponent(0.6)
        bloomShape.strokeColor = color.withAlphaComponent(0.25)
        bloomShape.lineWidth = 0
        bloomShape.glowWidth = 0
        bloomNode.addChild(bloomShape)
        bloomNode.shouldEnableEffects = true
        bloomNode.shouldRasterize = true
        bloomNode.shouldCenterFilter = true
        bloomNode.blendMode = .add
        bloomNode.zPosition = -0.5  // Between glow and beam
        addChild(bloomNode)

        // Main beam (on top)
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.85)
        beam.lineWidth = 0
        beam.glowWidth = 0
        beam.blendMode = .add
        addChild(beam)
    }
    
    private func updateGlowVisibility() {
        let shouldShow = firingState && glowEffectsEnabled
        glowShell.isHidden = !shouldShow
        if !shouldShow {
            glowShell.isPaused = true
        } else {
            glowShell.isPaused = false
        }
    }

    private func updateBlurVisibility() {
        let shouldShow = firingState && blurEffectsEnabled
        bloomNode.isHidden = !shouldShow
        bloomNode.shouldEnableEffects = shouldShow
        if !shouldShow {
            bloomNode.isPaused = true
        } else {
            bloomNode.isPaused = false
        }
    }
    
    var areAfterimagesEnabled: Bool {
        afterimageEffectsEnabled
    }
}

final class SweepingLaserNode: BaseLaserNode {
    private let spec: Level.Laser.Sweeper
    private let thicknessScale: CGFloat
    private var startPoint: CGPoint = .zero
    private var endPoint: CGPoint = .zero
    private var motionActive = false

    init(spec: Level.Laser.Sweeper, thicknessScale: CGFloat, color: SKColor) {
        self.spec = spec
        self.thicknessScale = thicknessScale
        super.init(color: color)
        glowShell.fillColor = color.withAlphaComponent(0.45)
        glowShell.strokeColor = color.withAlphaComponent(0.2)
        bloomShape.fillColor = color.withAlphaComponent(0.65)
        bloomShape.strokeColor = color.withAlphaComponent(0.25)
        lightNode.falloff = 0.7
        lightNode.ambientColor = color.withAlphaComponent(0.2)
        lightNode.lightColor = color.withAlphaComponent(0.95)
        lightNode.alpha = 1.0
        startGlowShimmer()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func startMotion() {
        motionActive = true
        restartMotion()
        if isLaserActive && areAfterimagesEnabled {
            startAfterimageLoop()
        }
    }
    
    private var isLaserActive: Bool {
        !beam.isHidden
    }
    
    override func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let length = hypot(transform.frame.width, transform.frame.height) * 1.1
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        beam.path = CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
        beam.glowWidth = thickness * 2.2  // This creates the blur effect!
        let glowRect = rect.insetBy(dx: -thickness, dy: -thickness)
        glowShell.path = CGPath(roundedRect: glowRect, cornerWidth: thickness * 1.3, cornerHeight: thickness * 1.3, transform: nil)
        glowShell.lineWidth = 0
        bloomShape.path = beam.path
        bloomShape.position = beam.position
        let blurRadius = max(thickness * 1.5, 6)
        updateBloomFilter(radius: blurRadius)
        startPoint = transform.point(from: spec.start)
        endPoint = transform.point(from: spec.end)
        position = startPoint
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        beam.zRotation = atan2(dy, dx) + (.pi / 2)
        glowShell.position = beam.position
        glowShell.zRotation = beam.zRotation
        bloomNode.position = beam.position
        bloomNode.zRotation = beam.zRotation
        lightNode.position = .zero
        if motionActive {
            restartMotion()
        }
    }
    
    private func restartMotion() {
        removeAction(forKey: "patrol")
        guard startPoint != endPoint else { return }
        let duration = max(spec.sweepSeconds, 0.05)
        let forward = SKAction.move(to: endPoint, duration: duration)
        forward.timingMode = .easeInEaseOut
        let backward = SKAction.move(to: startPoint, duration: duration)
        backward.timingMode = .easeInEaseOut
        let loop = SKAction.sequence([forward, backward])
        run(SKAction.repeatForever(loop), withKey: "patrol")
    }
    
    override func didActivateLaser() {
        guard areAfterimagesEnabled else { return }
        if action(forKey: "afterimage") == nil {
            startAfterimageLoop()
        }
    }

    override func didDeactivateLaser() {
        removeAction(forKey: "afterimage")
    }
    
    override func startAfterimageLoop() {
        guard areAfterimagesEnabled else { return }
        removeAction(forKey: "afterimage")
        let wait = SKAction.wait(forDuration: 0.08)
        let spawn = SKAction.run { [weak self] in
            self?.spawnAfterimage()
        }
        run(SKAction.repeatForever(SKAction.sequence([spawn, wait])), withKey: "afterimage")
    }
    
    private func spawnAfterimage() {
        guard let path = beam.path, let scene = scene else { return }
        let ghost = SKShapeNode(path: path)
        ghost.position = position
        ghost.zRotation = beam.zRotation
        ghost.fillColor = color.withAlphaComponent(0.2)
        ghost.strokeColor = .clear
        ghost.glowWidth = 0
        ghost.lineWidth = 0
        ghost.blendMode = .add
        ghost.zPosition = zPosition - 0.1
        scene.addChild(ghost)
        ghost.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.6),
                SKAction.scale(by: 1.04, duration: 0.6)
            ]),
            SKAction.removeFromParent()
        ]))
    }
    
    private func startGlowShimmer() {
        glowShell.removeAction(forKey: "glowShimmer")
        let delay = Double.random(in: 0...0.4)
        let duration = Double.random(in: 1.0...1.4)
        let up = SKAction.group([
            SKAction.fadeAlpha(to: 0.75, duration: duration),
            SKAction.scaleX(to: 1.06, duration: duration),
            SKAction.scaleY(to: 1.08, duration: duration)
        ])
        let down = SKAction.group([
            SKAction.fadeAlpha(to: 0.35, duration: duration),
            SKAction.scaleX(to: 1.0, duration: duration),
            SKAction.scaleY(to: 1.0, duration: duration)
        ])
        let sequence = SKAction.sequence([up, down])
        glowShell.run(SKAction.sequence([SKAction.wait(forDuration: delay), SKAction.repeatForever(sequence)]), withKey: "glowShimmer")
        lightNode.removeAction(forKey: "lightShimmer")
        let lightSequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: duration),
            SKAction.fadeAlpha(to: 0.45, duration: duration)
        ])
        lightNode.run(SKAction.sequence([SKAction.wait(forDuration: delay), SKAction.repeatForever(lightSequence)]), withKey: "lightShimmer")
    }
    
}

final class RotatingLaserNode: BaseLaserNode {
    private let spec: Level.Laser.Rotor
    private let thicknessScale: CGFloat
    private var motionActive = false
    
    init(spec: Level.Laser.Rotor, thicknessScale: CGFloat, color: SKColor) {
        self.spec = spec
        self.thicknessScale = thicknessScale
        super.init(color: color)
        glowShell.fillColor = color.withAlphaComponent(0.4)
        glowShell.strokeColor = color.withAlphaComponent(0.18)
        bloomShape.fillColor = color.withAlphaComponent(0.6)
        bloomShape.strokeColor = color.withAlphaComponent(0.25)
        lightNode.falloff = 0.6
        lightNode.ambientColor = color.withAlphaComponent(0.2)
        lightNode.lightColor = color.withAlphaComponent(0.95)
        startGlowShimmer()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func startMotion() {
        guard spec.speedDegreesPerSecond != 0 else { return }
        motionActive = true
        restartSpin()
        if areAfterimagesEnabled {
            startAfterimageLoop()
        }
    }
    
    override func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let armLength = max(transform.frame.width, transform.frame.height) * 1.4
        let rect = CGRect(x: -thickness / 2, y: -armLength / 2, width: thickness, height: armLength)
        beam.path = CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
        beam.position = .zero
        beam.glowWidth = thickness * 2.1  // This creates the blur effect!
        let glowRect = rect.insetBy(dx: -thickness * 0.9, dy: -thickness * 0.9)
        glowShell.path = CGPath(roundedRect: glowRect, cornerWidth: thickness * 1.25, cornerHeight: thickness * 1.25, transform: nil)
        glowShell.lineWidth = 0
        glowShell.position = .zero
        bloomShape.path = beam.path
        bloomShape.position = beam.position
        let blurRadius = max(thickness * 1.4, 6)
        updateBloomFilter(radius: blurRadius)
        bloomNode.position = .zero
        lightNode.position = .zero
        position = transform.point(from: spec.center)
        zRotation = CGFloat(spec.initialAngleDegrees * .pi / 180)
        if motionActive {
            restartSpin()
        }
    }
    
    private func restartSpin() {
        removeAction(forKey: "spin")
        guard spec.speedDegreesPerSecond != 0 else { return }
        let direction: CGFloat = spec.speedDegreesPerSecond > 0 ? -1 : 1
        let degreesPerSecond = abs(spec.speedDegreesPerSecond)
        let duration = Double(360) / max(degreesPerSecond, 0.01)
        let rotation = SKAction.rotate(byAngle: direction * (.pi * 2), duration: duration)
        run(SKAction.repeatForever(rotation), withKey: "spin")
    }
    
    override func didActivateLaser() {
        guard areAfterimagesEnabled else { return }
        if action(forKey: "afterimage") == nil {
            startAfterimageLoop()
        }
    }

    override func didDeactivateLaser() {
        removeAction(forKey: "afterimage")
    }

    override func startAfterimageLoop() {
        guard areAfterimagesEnabled else { return }
        removeAction(forKey: "afterimage")
        let wait = SKAction.wait(forDuration: 0.1)
        let spawn = SKAction.run { [weak self] in
            self?.spawnAfterimage()
        }
        run(SKAction.repeatForever(SKAction.sequence([spawn, wait])), withKey: "afterimage")
    }

    private func spawnAfterimage() {
        guard let path = beam.path, let scene = scene else { return }
        let ghost = SKShapeNode(path: path)
        ghost.position = position
        ghost.zRotation = zRotation
        ghost.fillColor = color.withAlphaComponent(0.18)
        ghost.strokeColor = .clear
        ghost.glowWidth = 0
        ghost.lineWidth = 0
        ghost.blendMode = .add
        ghost.zPosition = zPosition - 0.1
        scene.addChild(ghost)
        ghost.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.7),
                SKAction.scale(by: 1.05, duration: 0.7)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func startGlowShimmer() {
        glowShell.removeAction(forKey: "rotorGlow")
        let duration = Double.random(in: 0.9...1.3)
        let up = SKAction.group([
            SKAction.fadeAlpha(to: 0.65, duration: duration),
            SKAction.scaleX(to: 1.08, duration: duration),
            SKAction.scaleY(to: 1.08, duration: duration)
        ])
        let down = SKAction.group([
            SKAction.fadeAlpha(to: 0.35, duration: duration),
            SKAction.scaleX(to: 1.0, duration: duration),
            SKAction.scaleY(to: 1.0, duration: duration)
        ])
        let sequence = SKAction.sequence([up, down])
        glowShell.run(SKAction.repeatForever(sequence), withKey: "rotorGlow")
        lightNode.removeAction(forKey: "rotorLight")
        let lightSequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: duration),
            SKAction.fadeAlpha(to: 0.45, duration: duration)
        ])
        lightNode.run(SKAction.repeatForever(lightSequence), withKey: "rotorLight")
    }
}

final class SegmentLaserNode: BaseLaserNode {
    private let spec: Level.Laser.Segment
    private let thicknessScale: CGFloat
    
    init(spec: Level.Laser.Segment, thicknessScale: CGFloat, color: SKColor) {
        self.spec = spec
        self.thicknessScale = thicknessScale
        super.init(color: color)
        glowShell.fillColor = color.withAlphaComponent(0.4)
        glowShell.strokeColor = color.withAlphaComponent(0.2)
        bloomShape.fillColor = color.withAlphaComponent(0.5)
        bloomShape.strokeColor = color.withAlphaComponent(0.18)
        lightNode.falloff = 0.9
        lightNode.ambientColor = color.withAlphaComponent(0.2)
        lightNode.lightColor = color.withAlphaComponent(0.9)
        startGlowShimmer()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let thicknessInset = thickness * 0.6
        let start = transform.point(from: spec.start)
        let end = transform.point(from: spec.end)
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        beam.path = path.copy(strokingWithWidth: thickness, lineCap: .round, lineJoin: .round, miterLimit: 16)
        glowShell.path = path.copy(strokingWithWidth: thickness + thicknessInset, lineCap: .round, lineJoin: .round, miterLimit: 16)
        bloomShape.path = beam.path
        let blurRadius = max(thickness, 4)
        updateBloomFilter(radius: blurRadius)
        lightNode.position = .zero
    }
    
    private func startGlowShimmer() {
        glowShell.removeAction(forKey: "segmentGlow")
        let duration = Double.random(in: 1.1...1.6)
        let up = SKAction.group([
            SKAction.fadeAlpha(to: 0.65, duration: duration),
            SKAction.scaleX(to: 1.08, duration: duration),
            SKAction.scaleY(to: 1.08, duration: duration)
        ])
        let down = SKAction.group([
            SKAction.fadeAlpha(to: 0.35, duration: duration),
            SKAction.scaleX(to: 1.0, duration: duration),
            SKAction.scaleY(to: 1.0, duration: duration)
        ])
        let sequence = SKAction.sequence([up, down])
        glowShell.run(SKAction.repeatForever(sequence), withKey: "segmentGlow")
        lightNode.removeAction(forKey: "segmentLight")
        let lightSequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: duration),
            SKAction.fadeAlpha(to: 0.45, duration: duration)
        ])
        lightNode.run(SKAction.repeatForever(lightSequence), withKey: "segmentLight")
    }
}
