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
                afterimageEnabled: false
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

        if let rayLaser = spec as? Level.RayLaser {
            node = RayLaserNode(laser: rayLaser, thicknessScale: thickness, color: color)
        } else if let segmentLaser = spec as? Level.SegmentLaser {
            node = SegmentLaserNode(laser: segmentLaser, thicknessScale: thickness, color: color)
        } else {
            return nil
        }

        node.alpha = 0
        node.run(SKAction.fadeIn(withDuration: 0.2))
        node.addLight()
        node.configureVisualEffects(
            glowEnabled: settings.glowEnabled,
            blurEnabled: settings.blurEnabled,
            afterimageEnabled: false
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
            runtime.advance(delta: delta, timelineTime: timelineSeconds)
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
    
    mutating func advance(delta: TimeInterval, timelineTime: TimeInterval) {
        cadence?.advance(by: delta)
        applyFiringState(immediate: false)

        // Update node positions for moving endpoints
        if let rayNode = node as? RayLaserNode {
            rayNode.updatePosition(at: timelineTime)
        } else if let segmentNode = node as? SegmentLaserNode {
            segmentNode.updatePosition(at: timelineTime)
        }
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
    private let steps: [Level.CadenceStep]
    private var index: Int = 0
    private var elapsed: Double = 0
    private var locked = false

    init(steps: [Level.CadenceStep]) {
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

// MARK: - Endpoint Path Helpers

private extension Level.EndpointPath {
    /// Evaluate the position along the path at a given time
    func position(at time: TimeInterval, transform: NormalizedLayoutTransform) -> CGPoint {
        guard !points.isEmpty else { return .zero }

        if isStationary {
            return transform.point(from: points[0])
        }

        // Linear path between two points
        guard points.count >= 2, let cycleSeconds = cycleSeconds, cycleSeconds > 0 else {
            return transform.point(from: points[0])
        }

        // cycleSeconds is a full round-trip (0 -> 1 -> 0)
        let cycleTime = time.truncatingRemainder(dividingBy: cycleSeconds)
        let normalizedTime = cycleTime / cycleSeconds  // 0 to 1 over full cycle

        // First half: ease from 0 to 1, second half: ease from 1 to 0
        var t: Double
        if normalizedTime < 0.5 {
            // Forward: 0 -> 1 (first half of cycle)
            let halfT = normalizedTime * 2  // 0 to 1
            // Apply easeInOut for smooth acceleration/deceleration
            t = halfT < 0.5
                ? 2 * halfT * halfT
                : 1 - pow(-2 * halfT + 2, 2) / 2
        } else {
            // Backward: 1 -> 0 (second half of cycle)
            let halfT = (normalizedTime - 0.5) * 2  // 0 to 1
            // Apply easeInOut for smooth acceleration/deceleration
            let easedT = halfT < 0.5
                ? 2 * halfT * halfT
                : 1 - pow(-2 * halfT + 2, 2) / 2
            t = 1 - easedT  // Reverse direction
        }

        // Interpolate between points
        let p0 = transform.point(from: points[0])
        let p1 = transform.point(from: points[1])
        let x = p0.x + (p1.x - p0.x) * t
        let y = p0.y + (p1.y - p0.y) * t

        return CGPoint(x: x, y: y)
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
    }
    
    private func setupNodes() {
        // Glow layer (behind beam)
        glowShell.fillColor = color.withAlphaComponent(0.5)
        glowShell.strokeColor = color.withAlphaComponent(0.25)
        glowShell.blendMode = .add
        glowShell.zPosition = -1
        addChild(glowShell)

        // Main beam (on top) - glowWidth will be adjusted based on blur setting
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.85)
        beam.glowWidth = 0  // Will be set dynamically based on blur
        beam.blendMode = .add
        addChild(beam)
    }
    
    private func updateGlowVisibility() {
        let shouldShow = firingState && glowEffectsEnabled
        glowShell.isHidden = !shouldShow
        glowShell.isPaused = !shouldShow
    }

    private func updateBlurVisibility() {
        // Blur effect is handled by adjusting glowWidth in configureLineLaser
    }
    
    var areAfterimagesEnabled: Bool {
        afterimageEffectsEnabled
    }

    // Helper for line-based lasers (sweepers and segments)
    func configureLineLaser(start: CGPoint, end: CGPoint, thickness: CGFloat) {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        beam.path = path.copy(strokingWithWidth: thickness, lineCap: .round, lineJoin: .round, miterLimit: 16)
        // Adjust beam glow based on blur setting
        beam.glowWidth = blurEffectsEnabled ? thickness * 3.5 : 0

        let glowInset = thickness * 0.6
        glowShell.path = path.copy(strokingWithWidth: thickness + glowInset, lineCap: .round, lineJoin: .round, miterLimit: 16)
        glowShell.glowWidth = blurEffectsEnabled ? thickness * 1.5 : 0

        // Only reset positions, not rotations - child nodes should inherit parent rotation
        glowShell.position = .zero
        beam.position = .zero
    }
}


final class RayLaserNode: BaseLaserNode {
    private let laser: Level.RayLaser
    private let thicknessScale: CGFloat
    private var currentTransform: NormalizedLayoutTransform?
    private var elapsedTime: TimeInterval = 0
    private var motionActive = false

    init(laser: Level.RayLaser, thicknessScale: CGFloat, color: SKColor) {
        self.laser = laser
        self.thicknessScale = thicknessScale
        super.init(color: color)
        // Glow/bloom colors are set in setupNodes(), only customize lighting here
        lightNode.falloff = 0.6
        lightNode.ambientColor = color.withAlphaComponent(0.2)
        lightNode.lightColor = color.withAlphaComponent(0.95)
        startGlowShimmer()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func startMotion() {
        motionActive = true
    }

    override func updateLayout(using transform: NormalizedLayoutTransform) {
        currentTransform = transform
        updatePosition(at: elapsedTime)
    }

    func updatePosition(at time: TimeInterval) {
        guard let transform = currentTransform else { return }
        elapsedTime = time

        let thickness = max(transform.length(from: thicknessScale), 1)

        // Ray extends in both directions (2x screen diagonal for "infinite" effect)
        let rayLength = sqrt(pow(transform.frame.width, 2) + pow(transform.frame.height, 2)) * 2
        configureLineLaser(start: CGPoint(x: 0, y: -rayLength / 2), end: CGPoint(x: 0, y: rayLength / 2), thickness: thickness)

        lightNode.position = .zero

        // Update endpoint position
        let endpointPos = laser.endpoint.position(at: time + laser.endpoint.t, transform: transform)
        position = endpointPos

        // Update rotation
        let baseAngle = laser.effectiveInitialAngle()
        let rotation: CGFloat
        if motionActive && laser.rotationSpeed != 0 {
            rotation = CGFloat(baseAngle + laser.rotationSpeed * time)
        } else {
            rotation = CGFloat(baseAngle)
        }
        zRotation = rotation

        // Explicitly set rotation for child nodes to ensure they rotate properly
        glowShell.zRotation = rotation
        beam.zRotation = rotation
    }

    private func startGlowShimmer() {
        // Use only alpha animations to avoid visual artifacts from scaling
        glowShell.removeAction(forKey: "rotorGlow")
        let duration = Double.random(in: 0.9...1.3)
        let up = SKAction.fadeAlpha(to: 0.65, duration: duration)
        let down = SKAction.fadeAlpha(to: 0.35, duration: duration)
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
    private let laser: Level.SegmentLaser
    private let thicknessScale: CGFloat
    private var currentTransform: NormalizedLayoutTransform?
    private var elapsedTime: TimeInterval = 0

    init(laser: Level.SegmentLaser, thicknessScale: CGFloat, color: SKColor) {
        self.laser = laser
        self.thicknessScale = thicknessScale
        super.init(color: color)
        // Glow/bloom colors are set in setupNodes(), only customize lighting here
        lightNode.falloff = 0.9
        lightNode.ambientColor = color.withAlphaComponent(0.2)
        lightNode.lightColor = color.withAlphaComponent(0.9)
        startGlowShimmer()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLayout(using transform: NormalizedLayoutTransform) {
        currentTransform = transform
        updatePosition(at: elapsedTime)
    }

    func updatePosition(at time: TimeInterval) {
        guard let transform = currentTransform else { return }
        elapsedTime = time

        let thickness = max(transform.length(from: thicknessScale), 1)

        // Evaluate both endpoints at current time
        let start = laser.startEndpoint.position(at: time + laser.startEndpoint.t, transform: transform)
        let end = laser.endEndpoint.position(at: time + laser.endEndpoint.t, transform: transform)

        configureLineLaser(start: start, end: end, thickness: thickness)

        // Keep node at origin since beam coordinates are in world space
        position = .zero
        zRotation = 0

        // Position light at midpoint of segment
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        lightNode.position = midpoint
    }

    private func startGlowShimmer() {
        // For segment lasers, paths are in world-space coordinates, so scale animations
        // don't work correctly (they scale around origin, not the laser's center).
        // Only use alpha animations.
        glowShell.removeAction(forKey: "segmentGlow")
        let duration = Double.random(in: 1.1...1.6)
        let up = SKAction.fadeAlpha(to: 0.65, duration: duration)
        let down = SKAction.fadeAlpha(to: 0.35, duration: duration)
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
