//
//  LaserScenes.swift
//  laserfingers
//
//  Created by Zach Snow on 11/9/25.
//

import SpriteKit
import UIKit

final class LaserGameScene: SKScene {
    private let level: Level
    private let session: GameSession
    private let settings: GameSettings
    
    private var buttonStates: [ButtonRuntime] = []
    private var laserStates: [LaserRuntime] = []
    private var laserIndexById: [String: Int] = [:]
    private var fingerSprites: [UITouch: FingerSprite] = [:]
    private var lastUpdateTime: TimeInterval = 0
    private let alertOverlay: SKSpriteNode = {
        let node = SKSpriteNode(color: SKColor(red: 1, green: 0.15, blue: 0.2, alpha: 1), size: .zero)
        node.alpha = 0
        node.zPosition = 50
        node.blendMode = .add
        node.isUserInteractionEnabled = false
        return node
    }()
    
    private enum AlertKind {
        case cancelled
        case zap
        case exhausted
    }
    
    private let zapCooldown: TimeInterval = 0.45
    
    init(level: Level, session: GameSession, settings: GameSettings) {
        self.level = level
        self.session = session
        self.settings = settings
        super.init(size: CGSize(width: 1920, height: 1080))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 8/255, green: 9/255, blue: 20/255, alpha: 1)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        if buttonStates.isEmpty {
            buildScene()
        }
        session.status = .running
        isUserInteractionEnabled = true
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
        updateAlertOverlayFrame()
    }
    
    private func buildScene() {
        removeAllChildren()
        fingerSprites.removeAll()
        session.fillPercentage = 0
        addBackground()
        addAlertOverlay()
        addButtons()
        spawnLasers()
    }
    
    private func addBackground() {
        let backdrop = SKSpriteNode(color: SKColor(red: 12/255, green: 6/255, blue: 25/255, alpha: 1), size: CGSize(width: size.width * 1.4, height: size.height * 1.4))
        backdrop.zPosition = -10
        backdrop.alpha = 0.9
        addChild(backdrop)
        
        let glow = SKShapeNode(rectOf: CGSize(width: size.width * 0.8, height: size.height * 0.8), cornerRadius: 40)
        glow.fillColor = SKColor(red: 0.2, green: 0, blue: 0.3, alpha: 0.4)
        glow.strokeColor = .clear
        glow.zPosition = -9
        addChild(glow)
    }
    
    private func addAlertOverlay() {
        updateAlertOverlayFrame()
        alertOverlay.removeAllActions()
        alertOverlay.alpha = 0
        alertOverlay.removeFromParent()
        addChild(alertOverlay)
    }
    
    private func updateAlertOverlayFrame() {
        alertOverlay.size = CGSize(width: size.width * 1.3, height: size.height * 1.3)
        alertOverlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }
    
    private func flashAlert(_ kind: AlertKind) {
        let targetAlpha: CGFloat
        switch kind {
        case .cancelled:
            alertOverlay.color = SKColor.white
            targetAlpha = 0.25
        case .zap:
            alertOverlay.color = SKColor(red: 1, green: 0.8, blue: 0.1, alpha: 1)
            targetAlpha = 0.45
        case .exhausted:
            alertOverlay.color = SKColor(red: 1, green: 0, blue: 0.05, alpha: 1)
            targetAlpha = 0.75
        }
        let fadeIn = SKAction.fadeAlpha(to: targetAlpha, duration: 0.05)
        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.35)
        alertOverlay.removeAction(forKey: "alertFlash")
        alertOverlay.run(SKAction.sequence([fadeIn, fadeOut]), withKey: "alertFlash")
    }
    
    private func currentLayoutTransform() -> NormalizedLayoutTransform? {
        NormalizedLayoutTransform(frame: frame)
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
        
        guard !level.lasers.isEmpty else {
            spawnLegacyLasers()
            return
        }
        
        for spec in level.lasers {
            guard var runtime = makeLaserRuntime(from: spec, transform: transform) else { continue }
            runtime.node.startMotion()
            runtime.applyFiringState(immediate: true)
            addChild(runtime.node)
            laserIndexById[spec.id] = laserStates.count
            laserStates.append(runtime)
        }
    }
    
    private func makeLaserRuntime(from spec: Level.Laser, transform: NormalizedLayoutTransform) -> LaserRuntime? {
        let color = SKColor.fromHex(spec.color, alpha: 0.75)
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
        node.updateLayout(using: transform)
        return LaserRuntime(spec: spec, node: node)
    }
    
    private func spawnLegacyLasers() {
        guard let transform = currentLayoutTransform() else { return }
        let count = max(1, min(4, level.difficulty))
        let colors = ["#FF5A82", "#FFAA2C", "#5AE0FF", "#AC7BFF"]
        for index in 0..<count {
            let axis = (index + level.difficulty) % 3
            let fraction = CGFloat(index + 1) / CGFloat(count + 1)
            let sweepSeconds = 2.4 + Double(index) * 0.45
            let start: Level.NormalizedPoint
            let end: Level.NormalizedPoint
            switch axis {
            case 0: // horizontal
                let y = -0.8 + fraction * 1.6
                start = Level.NormalizedPoint(x: -0.95, y: y)
                end = Level.NormalizedPoint(x: 0.95, y: y)
            case 1: // vertical
                let x = -0.9 + fraction * 1.8
                start = Level.NormalizedPoint(x: x, y: -1.3)
                end = Level.NormalizedPoint(x: x, y: 1.3)
            default: // diagonal
                start = Level.NormalizedPoint(x: -0.95, y: -1.2 + fraction * 0.4)
                end = Level.NormalizedPoint(x: 0.95, y: 1.2 - fraction * 0.4)
            }
            let spec = Level.Laser(
                id: "legacy-\(index)",
                color: colors[index % colors.count],
                thickness: 0.015,
                cadence: nil,
                kind: .sweeper(Level.Laser.Sweeper(start: start, end: end, sweepSeconds: sweepSeconds))
            )
            guard var runtime = makeLaserRuntime(from: spec, transform: transform) else { continue }
            runtime.node.startMotion()
            runtime.applyFiringState(immediate: true)
            addChild(runtime.node)
            laserIndexById[spec.id] = laserStates.count
            laserStates.append(runtime)
        }
    }
    
    private func layoutScene() {
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
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.status == .running else { return }
        for touch in touches {
            if !session.hasInfiniteSlots {
                guard fingerSprites.count < max(1, session.touchAllowance) else { continue }
            }
            let location = touch.location(in: self)
            let node = makeFingerSprite(at: location)
            addChild(node)
            var data = FingerSprite(node: node, lastZapTime: 0)
            data.node.alpha = 0.0
            data.node.run(SKAction.fadeAlpha(to: 1.0, duration: 0.1))
            fingerSprites[touch] = data
        }
        session.activeTouches = fingerSprites.count
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.status == .running else { return }
        for touch in touches {
            guard var sprite = fingerSprites[touch] else { continue }
            let location = touch.location(in: self)
            sprite.node.position = location
            fingerSprites[touch] = sprite
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeTouches(touches)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !fingerSprites.isEmpty {
            flashAlert(.cancelled)
        }
        removeTouches(touches)
    }
    
    private func removeTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let sprite = fingerSprites.removeValue(forKey: touch) else { continue }
            sprite.node.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.removeFromParent()
            ]))
        }
        session.activeTouches = fingerSprites.count
    }
    
    private func makeFingerSprite(at point: CGPoint) -> SKShapeNode {
        let radius: CGFloat = 22
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = SKColor.white.withAlphaComponent(0.25)
        node.strokeColor = SKColor.white.withAlphaComponent(0.45)
        node.lineWidth = 2
        node.position = point
        node.zPosition = 20
        node.glowWidth = 4
        return node
    }
    
    // MARK: - Game Loop
    
    override func update(_ currentTime: TimeInterval) {
        guard session.status == .running else { return }
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = min(currentTime - lastUpdateTime, 1 / 20)
        lastUpdateTime = currentTime
        
        updateButtons(delta: delta)
        updateLasers(delta: delta)
        checkLaserHits(currentTime: currentTime)
        evaluateWinCondition()
    }
    
    private func updateButtons(delta: TimeInterval) {
        guard !buttonStates.isEmpty else {
            session.fillPercentage = 0
            return
        }
        let touchPoints = fingerSprites.values.map { $0.node.position }
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
            } else if !isTouching && wasTouching {
                runEffects(for: runtime.spec, trigger: .touchEnded)
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
            }
            if turnedOff {
                runEffects(for: runtime.spec, trigger: .turnedOff)
            }
            buttonStates[index] = runtime
        }
        let requiredButtons = buttonStates.filter { $0.spec.required }
        let trackedButtons = requiredButtons.isEmpty ? buttonStates : requiredButtons
        if trackedButtons.isEmpty {
            session.fillPercentage = 0
        } else {
            let total = trackedButtons.reduce(CGFloat(0)) { $0 + $1.charge }
            session.fillPercentage = total / CGFloat(trackedButtons.count)
        }
    }
    
    private func updateLasers(delta: TimeInterval) {
        guard !laserStates.isEmpty else { return }
        for index in laserStates.indices {
            var runtime = laserStates[index]
            runtime.advance(delta: delta)
            laserStates[index] = runtime
        }
    }
    
    private func evaluateWinCondition() {
        guard session.status == .running else { return }
        let requiredButtons = buttonStates.filter { $0.spec.required }
        let trackedButtons = requiredButtons.isEmpty ? buttonStates : requiredButtons
        guard !trackedButtons.isEmpty else { return }
        if trackedButtons.allSatisfy({ $0.isFullyCharged }) {
            completeLevel()
        }
    }
    
    private func checkLaserHits(currentTime: TimeInterval) {
        for (touch, sprite) in fingerSprites {
            guard currentTime - sprite.lastZapTime > zapCooldown else { continue }
            let position = sprite.node.position
            if laserStates.contains(where: { $0.node.isDangerous(at: position, in: self) }) {
                registerZap(for: touch, currentTime: currentTime)
            }
        }
    }
    
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
    
    private func registerZap(for touch: UITouch, currentTime: TimeInterval) {
        guard var sprite = fingerSprites[touch] else { return }
        sprite.lastZapTime = currentTime
        fingerSprites[touch] = sprite
        
        let flash = SKAction.sequence([
            SKAction.run { sprite.node.fillColor = .red },
            SKAction.wait(forDuration: 0.1),
            SKAction.run { sprite.node.fillColor = SKColor.white.withAlphaComponent(0.25) }
        ])
        sprite.node.run(flash)
        
        if settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        
        if session.registerZap() {
            flashAlert(.exhausted)
            failLevel()
        } else {
            flashAlert(.zap)
        }
    }
    
    private func completeLevel() {
        guard session.status == .running else { return }
        session.status = .won
        isUserInteractionEnabled = false
        buttonStates.forEach { $0.node.celebrate() }
    }
    
    private func failLevel() {
        guard session.status == .running else { return }
        session.status = .lost
        isUserInteractionEnabled = false
        let flash = SKAction.sequence([
            SKAction.colorize(with: .red, colorBlendFactor: 0.8, duration: 0.05),
            SKAction.wait(forDuration: 0.1),
            SKAction.colorize(withColorBlendFactor: 0, duration: 0.2)
        ])
        run(flash)
    }
}

extension LaserGameScene {
    func setScenePaused(_ paused: Bool) {
        isPaused = paused
        isUserInteractionEnabled = !paused && session.status == .running
    }
}

private typealias LaserNode = SKNode & LaserObstacle

private protocol LaserObstacle: AnyObject {
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool
    func startMotion()
    func setFiring(active: Bool)
    func updateLayout(using transform: NormalizedLayoutTransform)
}

extension LaserObstacle {
    func startMotion() {}
    func setFiring(active: Bool) {}
    func updateLayout(using transform: NormalizedLayoutTransform) {}
}

// MARK: - Menu Background

final class MenuBackgroundScene: SKScene {
    private var lasers: [LaserNode] = []
    
    override init() {
        super.init(size: CGSize(width: 1920, height: 1080))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 8/255, green: 9/255, blue: 20/255, alpha: 1)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        if lasers.isEmpty {
            setup()
        }
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard let transform = NormalizedLayoutTransform(frame: frame) else { return }
        for laser in lasers {
            laser.updateLayout(using: transform)
        }
    }
    
    private func setup() {
        let gradient = SKShapeNode(rectOf: CGSize(width: size.width * 1.1, height: size.height * 1.1), cornerRadius: 48)
        gradient.fillColor = SKColor(red: 0.05, green: 0, blue: 0.1, alpha: 0.6)
        gradient.strokeColor = .clear
        gradient.zPosition = -5
        addChild(gradient)
        
        guard let transform = NormalizedLayoutTransform(frame: frame) else { return }
        lasers = (0..<3).map { index in
            let horizontal = index % 2 == 0
            let fraction = CGFloat(index + 1) / 4
            let start: Level.NormalizedPoint
            let end: Level.NormalizedPoint
            if horizontal {
                let y = -0.8 + fraction * 1.6
                start = Level.NormalizedPoint(x: -0.95, y: y)
                end = Level.NormalizedPoint(x: 0.95, y: y)
            } else {
                let x = -0.8 + fraction * 1.6
                start = Level.NormalizedPoint(x: x, y: -1.3)
                end = Level.NormalizedPoint(x: x, y: 1.3)
            }
            let spec = Level.Laser.Sweeper(start: start, end: end, sweepSeconds: 4 + Double(index))
            let color = SKColor(hue: 0.85 - CGFloat(index) * 0.1, saturation: 0.7, brightness: 1, alpha: 0.5)
            let node = SweepingLaserNode(spec: spec, thicknessScale: 0.02, color: color)
            addChild(node)
            node.updateLayout(using: transform)
            node.startMotion()
            return node
        }
        
        let starfield = SKEmitterNode()
        starfield.particleColor = SKColor.white
        starfield.particleColorBlendFactor = 1
        starfield.particleAlpha = 0.1
        starfield.particleScale = 0.5
        starfield.particleLifetime = 6
        starfield.particleBirthRate = 8
        starfield.particleSpeed = 12
        starfield.particleSpeedRange = 20
        starfield.position = CGPoint(x: frame.midX, y: frame.midY)
        starfield.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        starfield.zPosition = -2
        addChild(starfield)
    }
}

// MARK: - Helpers

private struct FingerSprite {
    let node: SKShapeNode
    var lastZapTime: TimeInterval
}

private struct ButtonRuntime {
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

private final class ButtonNode: SKNode {
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
    
    init(button: Level.Button, transform: NormalizedLayoutTransform) {
        self.button = button
        self.colorSpec = button.color
        super.init()
        buildAreas(from: button.hitAreas)
        updateLayout(transform: transform)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateLayout(transform: NormalizedLayoutTransform) {
        position = transform.point(from: button.position)
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
        let strokeAlpha: CGFloat = isTouching ? 0.95 : 0.65
        let color = SKColor.fromHex(colorSpec.rim ?? colorSpec.fill, alpha: strokeAlpha)
        for index in areas.indices {
            areas[index].outline.strokeColor = color
        }
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
            outline.fillColor = SKColor.black.withAlphaComponent(0.4)
            outline.lineWidth = 2
            outline.strokeColor = SKColor.fromHex(colorSpec.rim ?? colorSpec.fill, alpha: 0.65)
            
            let fill = SKShapeNode()
            fill.fillColor = SKColor.fromHex(colorSpec.fill)
            fill.strokeColor = .clear
            fill.alpha = 0.25
            
            let glow = SKShapeNode()
            glow.fillColor = SKColor.fromHex(colorSpec.glow ?? colorSpec.fill, alpha: 0.3)
            glow.strokeColor = .clear
            glow.alpha = 0.1
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
}

private struct LaserRuntime {
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
        guard !steps.isEmpty, !locked else { return }
        elapsed += delta
        guard let duration = steps[index].duration else {
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
    
    var isOn: Bool {
        guard !steps.isEmpty else { return true }
        return steps[index].state == .on
    }
}

private struct NormalizedLayoutTransform {
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


private final class SweepingLaserNode: SKNode, LaserObstacle {
    private let spec: Level.Laser.Sweeper
    private let thicknessScale: CGFloat
    private let color: SKColor
    private let beam: SKShapeNode
    private var startPoint: CGPoint = .zero
    private var endPoint: CGPoint = .zero
    private var isFiring = true
    private var motionActive = false
    
    init(spec: Level.Laser.Sweeper, thicknessScale: CGFloat, color: SKColor) {
        self.spec = spec
        self.thicknessScale = thicknessScale
        self.color = color
        beam = SKShapeNode()
        super.init()
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.85)
        addChild(beam)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func startMotion() {
        motionActive = true
        restartMotion()
    }
    
    func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let length = hypot(transform.frame.width, transform.frame.height) * 1.1
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        beam.path = CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
        beam.glowWidth = thickness * 0.8
        startPoint = transform.point(from: spec.start)
        endPoint = transform.point(from: spec.end)
        position = startPoint
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        beam.zRotation = atan2(dy, dx) + (.pi / 2)
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
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        guard isFiring else { return false }
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    func setFiring(active: Bool) {
        isFiring = active
        beam.alpha = active ? 1.0 : 0.05
    }
}

private final class RotatingLaserNode: SKNode, LaserObstacle {
    private let spec: Level.Laser.Rotor
    private let thicknessScale: CGFloat
    private let color: SKColor
    private let beam: SKShapeNode
    private var isFiring = true
    private var motionActive = false
    
    init(spec: Level.Laser.Rotor, thicknessScale: CGFloat, color: SKColor) {
        self.spec = spec
        self.thicknessScale = thicknessScale
        self.color = color
        beam = SKShapeNode()
        super.init()
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.85)
        addChild(beam)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func startMotion() {
        guard spec.speedDegreesPerSecond != 0 else { return }
        motionActive = true
        restartSpin()
    }
    
    func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let armLength = max(transform.frame.width, transform.frame.height) * 1.4
        let rect = CGRect(x: -thickness / 2, y: 0, width: thickness, height: armLength)
        beam.path = CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
        beam.position = CGPoint(x: 0, y: armLength / 2)
        beam.glowWidth = thickness * 0.9
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
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        guard isFiring else { return false }
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    func setFiring(active: Bool) {
        isFiring = active
        beam.alpha = active ? 1.0 : 0.05
    }
}

private final class SegmentLaserNode: SKNode, LaserObstacle {
    private let spec: Level.Laser.Segment
    private let thicknessScale: CGFloat
    private let color: SKColor
    private let beam: SKShapeNode
    private var isFiring = true
    
    init(spec: Level.Laser.Segment, thicknessScale: CGFloat, color: SKColor) {
        self.spec = spec
        self.thicknessScale = thicknessScale
        self.color = color
        beam = SKShapeNode()
        super.init()
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.85)
        addChild(beam)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func startMotion() {}
    
    func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let startPoint = transform.point(from: spec.start)
        let endPoint = transform.point(from: spec.end)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = hypot(dx, dy)
        beam.path = CGPath(
            roundedRect: CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness),
            cornerWidth: thickness / 2,
            cornerHeight: thickness / 2,
            transform: nil
        )
        beam.position = .zero
        beam.glowWidth = thickness
        position = CGPoint(x: (startPoint.x + endPoint.x) / 2, y: (startPoint.y + endPoint.y) / 2)
        zRotation = atan2(dy, dx)
    }
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        guard isFiring else { return false }
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    func setFiring(active: Bool) {
        isFiring = active
        beam.alpha = active ? 1.0 : 0.05
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
