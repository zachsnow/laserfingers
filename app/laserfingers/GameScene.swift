//
//  LaserScenes.swift
//  laserfingers
//
//  Created by Zach Snow on 11/9/25.
//

import Foundation
import SpriteKit
import UIKit

private enum LightingMask {
    static let button: UInt32 = 1 << 0
    static let laser: UInt32 = 1 << 1
}

final class LaserGameScene: SKScene {
    private let level: Level
    private let session: GameSession
    private let settings: GameSettings
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
        backgroundColor = .black
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
        updateBackgroundImageLayout()
        updateAmbientLightLayout()
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
        backgroundImageNode.removeFromParent()
        guard let texture = loadBackgroundTexture() else {
            backgroundColor = .black
            addAmbientLight()
            return
        }
        backgroundColor = .black
        backgroundImageNode.texture = texture
        backgroundImageNode.size = texture.size()
        addChild(backgroundImageNode)
        updateBackgroundImageLayout()
        addAmbientLight()
    }
    
    private func loadBackgroundTexture() -> SKTexture? {
        guard let path = resolveBackgroundImagePath() else { return nil }
        return SKTexture(imageNamed: path)
    }
    
    private func resolveBackgroundImagePath() -> String? {
        guard let backgroundImage = level.backgroundImage else { return nil }
        guard let directory = level.directory else {
            FatalErrorReporter.report("Level \(level.id) specified background image \(backgroundImage) but no source directory was recorded.")
            return nil
        }
        let resolvedURL = URL(fileURLWithPath: backgroundImage, relativeTo: directory).standardizedFileURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: resolvedURL.path) else {
            FatalErrorReporter.report("Background image \(backgroundImage) for level \(level.id) does not exist at \(resolvedURL.path).")
            return nil
        }
        guard let bundleRoot = Bundle.main.resourceURL?.standardizedFileURL else {
            FatalErrorReporter.report("Unable to resolve bundle resource path when loading level \(level.id) background image.")
            return nil
        }
        let resourcePath = resolvedURL.path
        let bundlePath = bundleRoot.path
        guard resourcePath.hasPrefix(bundlePath) else {
            FatalErrorReporter.report("Background image \(backgroundImage) for level \(level.id) resolves outside of the app bundle.")
            return nil
        }
        guard resourcePath.count > bundlePath.count else {
            FatalErrorReporter.report("Failed to compute relative path for background image \(backgroundImage) in level \(level.id).")
            return nil
        }
        let startIndex = resourcePath.index(resourcePath.startIndex, offsetBy: bundlePath.count + 1)
        guard startIndex <= resourcePath.endIndex else {
            FatalErrorReporter.report("Failed to compute relative path for background image \(backgroundImage) in level \(level.id).")
            return nil
        }
        return String(resourcePath[startIndex...])
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
            triggerHaptics(.warning)
        case .zap:
            alertOverlay.color = SKColor(red: 1, green: 0.8, blue: 0.1, alpha: 1)
            targetAlpha = 0.45
            triggerHaptics(.zap)
        case .exhausted:
            alertOverlay.color = SKColor(red: 1, green: 0, blue: 0.05, alpha: 1)
            targetAlpha = 0.75
            triggerHaptics(.death)
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
        node.updateLayout(using: transform)
        return LaserRuntime(spec: spec, node: node)
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
            let data = FingerSprite(node: node, lastZapTime: 0, previousPosition: location)
            data.node.alpha = 0.0
            data.node.run(SKAction.fadeAlpha(to: 1.0, duration: 0.1))
            fingerSprites[touch] = data
        }
        session.activeTouches = fingerSprites.count
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.status == .running else { return }
        for touch in touches {
            guard let sprite = fingerSprites[touch] else { continue }
            let location = touch.location(in: self)
            var updated = sprite
            updated.previousPosition = sprite.node.position
            sprite.node.position = location
            fingerSprites[touch] = updated
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
        let node = SKShapeNode(circleOfRadius: FingerSprite.fingerRadius)
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
                triggerHaptics(.success)
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
        guard !laserStates.isEmpty else { return }
        let laserPolygons = laserStates.map { $0.node.collisionPolygons(in: self) }.flatMap { $0 }
        guard !laserPolygons.isEmpty else { return }
        for touch in Array(fingerSprites.keys) {
            guard var sprite = fingerSprites[touch] else { continue }
            if currentTime - sprite.lastZapTime <= zapCooldown {
                sprite.previousPosition = sprite.node.position
                fingerSprites[touch] = sprite
                continue
            }
            let capsule = Capsule(a: sprite.previousPosition, b: sprite.node.position, radius: FingerSprite.fingerRadius)
            sprite.previousPosition = sprite.node.position
            fingerSprites[touch] = sprite
            if capsule.intersectsAny(laserPolygons) {
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
        sprite.previousPosition = sprite.node.position
        fingerSprites[touch] = sprite
        
        let flash = SKAction.sequence([
            SKAction.run { sprite.node.fillColor = .red },
            SKAction.wait(forDuration: 0.1),
            SKAction.run { sprite.node.fillColor = SKColor.white.withAlphaComponent(0.25) }
        ])
        sprite.node.run(flash)
        
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
    
    private func triggerHaptics(_ event: HapticEvent) {
        guard settings.hapticsEnabled else { return }
        Haptics.shared.play(event)
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
    func collisionPolygons(in scene: SKScene) -> [Polygon]
}

extension LaserObstacle {
    func startMotion() {}
    func setFiring(active: Bool) {}
    func updateLayout(using transform: NormalizedLayoutTransform) {}
    func collisionPolygons(in scene: SKScene) -> [Polygon] { [] }
}

private class BaseLaserNode: SKNode, LaserObstacle {
    let color: SKColor
    let beam = SKShapeNode()
    let glowShell = SKShapeNode()
    let bloomNode = SKEffectNode()
    let bloomShape = SKShapeNode()
    let lightNode = SKLightNode()
    private var firingState = true
    
    init(color: SKColor) {
        self.color = color
        super.init()
        setupNodes()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupNodes() {
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.85)
        beam.glowWidth = 0
        beam.blendMode = .add
        
        glowShell.fillColor = color.withAlphaComponent(0.4)
        glowShell.strokeColor = color.withAlphaComponent(0.18)
        glowShell.blendMode = .add
        glowShell.zPosition = -1
        addChild(glowShell)
        
        bloomShape.fillColor = color.withAlphaComponent(0.6)
        bloomShape.strokeColor = color.withAlphaComponent(0.25)
        bloomShape.lineWidth = 0
        bloomShape.glowWidth = 0
        
        bloomNode.shouldRasterize = true
        bloomNode.shouldEnableEffects = true
        bloomNode.blendMode = .add
        bloomNode.zPosition = glowShell.zPosition + 0.5
        bloomNode.addChild(bloomShape)
        addChild(bloomNode)
        
        lightNode.categoryBitMask = LightingMask.laser
        lightNode.falloff = 0.7
        lightNode.ambientColor = color.withAlphaComponent(0.2)
        lightNode.lightColor = color.withAlphaComponent(0.95)
        lightNode.alpha = 1.0
        lightNode.isEnabled = true
        addChild(lightNode)
        
        addChild(beam)
    }
    
    func startMotion() {}
    
    func updateLayout(using transform: NormalizedLayoutTransform) {}
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        guard firingState else { return false }
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    func setFiring(active: Bool) {
        let stateChanged = firingState != active
        firingState = active
        updateVisualState(isActive: active)
        if stateChanged {
            if active {
                didActivateLaser()
            } else {
                didDeactivateLaser()
            }
        }
    }
    
    private func updateVisualState(isActive: Bool) {
        if isActive {
            beam.isHidden = false
            glowShell.isHidden = false
            bloomNode.isHidden = false
            beam.isPaused = false
            glowShell.isPaused = false
            bloomNode.isPaused = false
        } else {
            beam.isHidden = true
            glowShell.isHidden = true
            bloomNode.isHidden = true
            beam.isPaused = true
            glowShell.isPaused = true
            bloomNode.isPaused = true
        }
        updateLightState(isActive: isActive)
    }
    
    private func updateLightState(isActive: Bool) {
        if isActive {
            lightNode.isPaused = false
            lightNode.alpha = 1.0
            lightNode.isEnabled = true
        } else {
            lightNode.isEnabled = false
            lightNode.isPaused = true
        }
    }
    
    func didActivateLaser() {}
    func didDeactivateLaser() {}
    
    var isLaserActive: Bool { firingState }
    
    func updateBloomFilter(radius: CGFloat) {
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        bloomNode.filter = filter
    }
    
    func collisionPolygons(in scene: SKScene) -> [Polygon] {
        guard isLaserActive, let path = beam.path else { return [] }
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
}

// MARK: - Shared Background

private final class BackgroundLayer: SKNode {
    private let baseSprite: SKSpriteNode
    private let glowSprite: SKSpriteNode
    private let sweepNode: SKShapeNode
    private let flareOverlay: SKSpriteNode
    private let vignetteOverlay: SKSpriteNode
    private let centerLight: SKLightNode
    private let rimLight: SKLightNode
    
    override init() {
        let texture = SKTexture(imageNamed: "Images/bg.jpg")
        baseSprite = SKSpriteNode(texture: texture)
        glowSprite = SKSpriteNode(texture: texture)
        sweepNode = SKShapeNode()
        flareOverlay = SKSpriteNode(color: SKColor(red: 1, green: 0.35, blue: 1, alpha: 0.35), size: .zero)
        vignetteOverlay = SKSpriteNode(color: SKColor(white: 0, alpha: 0.55), size: .zero)
        centerLight = SKLightNode()
        rimLight = SKLightNode()
        super.init()
        setupNodes()
        startAmbientAnimations()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateLayout(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let padded = CGSize(width: size.width * 1.3, height: size.height * 1.3)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        baseSprite.size = padded
        baseSprite.position = center
        glowSprite.size = CGSize(width: padded.width * 1.05, height: padded.height * 1.05)
        glowSprite.position = center
        flareOverlay.size = CGSize(width: padded.width * 1.15, height: padded.height * 1.15)
        flareOverlay.position = center
        vignetteOverlay.size = CGSize(width: padded.width * 1.25, height: padded.height * 1.25)
        vignetteOverlay.position = center
        sweepNode.position = center
        let sweepWidth = max(padded.width * 0.22, 80)
        let sweepHeight = padded.height * 1.2
        let rect = CGRect(x: -sweepWidth / 2, y: -sweepHeight / 2, width: sweepWidth, height: sweepHeight)
        sweepNode.path = CGPath(roundedRect: rect, cornerWidth: sweepWidth * 0.4, cornerHeight: sweepWidth * 0.4, transform: nil)
        centerLight.position = center
        rimLight.position = center
        restartSweepAnimation(span: padded.width * 0.6)
    }
    
    private func setupNodes() {
        baseSprite.lightingBitMask = 0
        baseSprite.shadowedBitMask = 0
        baseSprite.shadowCastBitMask = 0
        baseSprite.zPosition = -30
        addChild(baseSprite)
        
        glowSprite.color = SKColor(red: 0.9, green: 0.25, blue: 1, alpha: 1)
        glowSprite.colorBlendFactor = 0.6
        glowSprite.alpha = 0.2
        glowSprite.blendMode = .add
        glowSprite.lightingBitMask = 0b11
        glowSprite.zPosition = baseSprite.zPosition + 1
        addChild(glowSprite)
        
        sweepNode.fillColor = SKColor(red: 0.9, green: 0.65, blue: 1, alpha: 0.45)
        sweepNode.strokeColor = SKColor(red: 1, green: 1, blue: 1, alpha: 0.35)
        sweepNode.glowWidth = 24
        sweepNode.lineWidth = 0
        sweepNode.blendMode = .add
        sweepNode.zPosition = glowSprite.zPosition + 1
        addChild(sweepNode)
        
        flareOverlay.blendMode = .add
        flareOverlay.alpha = 0.25
        flareOverlay.zPosition = sweepNode.zPosition + 1
        flareOverlay.lightingBitMask = 0
        addChild(flareOverlay)
        
        vignetteOverlay.blendMode = .multiply
        vignetteOverlay.alpha = 0.3
        vignetteOverlay.zPosition = flareOverlay.zPosition + 1
        vignetteOverlay.lightingBitMask = 0
        addChild(vignetteOverlay)
        
        centerLight.categoryBitMask = 0b10
        centerLight.falloff = 0.25
        centerLight.ambientColor = SKColor(red: 0.08, green: 0.0, blue: 0.15, alpha: 0.45)
        centerLight.lightColor = SKColor(red: 1, green: 0.65, blue: 1, alpha: 0.8)
        centerLight.zPosition = vignetteOverlay.zPosition + 1
        addChild(centerLight)
        
        rimLight.categoryBitMask = 0b10
        rimLight.falloff = 2.2
        rimLight.lightColor = SKColor(red: 0.35, green: 0.65, blue: 1, alpha: 0.5)
        rimLight.ambientColor = .clear
        rimLight.zPosition = centerLight.zPosition
        addChild(rimLight)
    }
    
    private func startAmbientAnimations() {
        glowSprite.removeAction(forKey: "glowPulse")
        let glowUp = SKAction.fadeAlpha(to: 0.4, duration: 2.6)
        let glowDown = SKAction.fadeAlpha(to: 0.15, duration: 2.0)
        glowSprite.run(SKAction.repeatForever(SKAction.sequence([glowUp, glowDown])), withKey: "glowPulse")
        
        flareOverlay.removeAction(forKey: "flarePulse")
        let flareUp = SKAction.fadeAlpha(to: 0.3, duration: 1.8)
        let flareDown = SKAction.fadeAlpha(to: 0.1, duration: 1.6)
        flareOverlay.run(SKAction.repeatForever(SKAction.sequence([flareUp, flareDown])), withKey: "flarePulse")
        
        centerLight.removeAction(forKey: "centerPulse")
        let lightUp = SKAction.fadeAlpha(to: 1.0, duration: 2.2)
        let lightDown = SKAction.fadeAlpha(to: 0.5, duration: 2.0)
        centerLight.alpha = 0.8
        centerLight.run(SKAction.repeatForever(SKAction.sequence([lightUp, lightDown])), withKey: "centerPulse")
    }
    
    private func restartSweepAnimation(span: CGFloat) {
        guard span > 0 else { return }
        sweepNode.removeAction(forKey: "lightSweep")
        let moveRight = SKAction.moveBy(x: span, y: span * 0.05, duration: 3.8)
        moveRight.timingMode = .easeInEaseOut
        let moveLeft = moveRight.reversed()
        moveLeft.timingMode = .easeInEaseOut
        let wait = SKAction.wait(forDuration: 0.6)
        let loop = SKAction.sequence([moveRight, wait, moveLeft, wait])
        sweepNode.run(SKAction.repeatForever(loop), withKey: "lightSweep")
    }
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
    static let fingerRadius: CGFloat = 22
    let node: SKShapeNode
    var lastZapTime: TimeInterval
    var previousPosition: CGPoint
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


private final class SweepingLaserNode: BaseLaserNode {
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
        if isLaserActive {
            startAfterimageLoop()
        }
    }
    
    override func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let length = hypot(transform.frame.width, transform.frame.height) * 1.1
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        beam.path = CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
        beam.glowWidth = thickness * 2.2
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
        if action(forKey: "afterimage") == nil {
            startAfterimageLoop()
        }
    }
    
    override func didDeactivateLaser() {
        removeAction(forKey: "afterimage")
    }
    
    private func startAfterimageLoop() {
        removeAction(forKey: "afterimage")
        let wait = SKAction.wait(forDuration: 0.08)
        let spawn = SKAction.run { [weak self] in
            self?.spawnAfterimage()
        }
        run(SKAction.repeatForever(SKAction.sequence([spawn, wait])), withKey: "afterimage")
    }
    
    private func spawnAfterimage() {
        guard let path = beam.path else { return }
        let ghost = SKShapeNode(path: path)
        ghost.position = beam.position
        ghost.zRotation = beam.zRotation
        ghost.fillColor = color.withAlphaComponent(0.35)
        ghost.strokeColor = color.withAlphaComponent(0.45)
        ghost.glowWidth = beam.glowWidth * 0.7
        ghost.lineWidth = beam.lineWidth
        ghost.zPosition = beam.zPosition - 1
        addChild(ghost)
        ghost.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.5),
                SKAction.scale(by: 1.03, duration: 0.5)
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

private final class RotatingLaserNode: BaseLaserNode {
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
        startAfterimageLoop()
    }
    
    override func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let armLength = max(transform.frame.width, transform.frame.height) * 1.4
        let rect = CGRect(x: -thickness / 2, y: -armLength / 2, width: thickness, height: armLength)
        beam.path = CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
        beam.position = .zero
        beam.glowWidth = thickness * 2.1
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
        if action(forKey: "afterimage") == nil {
            startAfterimageLoop()
        }
    }
    
    override func didDeactivateLaser() {
        removeAction(forKey: "afterimage")
    }

    private func startGlowShimmer() {
        glowShell.removeAction(forKey: "rotorGlow")
        let duration = Double.random(in: 0.9...1.3)
        let up = SKAction.group([
            SKAction.fadeAlpha(to: 0.7, duration: duration),
            SKAction.scaleX(to: 1.08, duration: duration),
            SKAction.scaleY(to: 1.08, duration: duration)
        ])
        let down = SKAction.group([
            SKAction.fadeAlpha(to: 0.35, duration: duration),
            SKAction.scaleX(to: 1.0, duration: duration),
            SKAction.scaleY(to: 1.0, duration: duration)
        ])
        glowShell.run(SKAction.repeatForever(SKAction.sequence([up, down])), withKey: "rotorGlow")
        lightNode.removeAction(forKey: "rotorLight")
        let lightSequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: duration),
            SKAction.fadeAlpha(to: 0.5, duration: duration)
        ])
        lightNode.run(SKAction.repeatForever(lightSequence), withKey: "rotorLight")
    }
    
    private func startAfterimageLoop() {
        removeAction(forKey: "afterimage")
        let wait = SKAction.wait(forDuration: 0.08)
        let spawn = SKAction.run { [weak self] in
            self?.spawnAfterimage()
        }
        run(SKAction.repeatForever(SKAction.sequence([spawn, wait])), withKey: "afterimage")
    }
    
    private func spawnAfterimage() {
        guard let path = beam.path else { return }
        let ghost = SKShapeNode(path: path)
        ghost.position = beam.position
        ghost.zRotation = beam.zRotation
        ghost.fillColor = color.withAlphaComponent(0.3)
        ghost.strokeColor = color.withAlphaComponent(0.4)
        ghost.glowWidth = beam.glowWidth * 0.7
        ghost.lineWidth = beam.lineWidth
        addChild(ghost)
        ghost.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }
    
}

private final class SegmentLaserNode: BaseLaserNode {
    private let spec: Level.Laser.Segment
    private let thicknessScale: CGFloat
    
    init(spec: Level.Laser.Segment, thicknessScale: CGFloat, color: SKColor) {
        self.spec = spec
        self.thicknessScale = thicknessScale
        super.init(color: color)
        glowShell.fillColor = color.withAlphaComponent(0.4)
        glowShell.strokeColor = color.withAlphaComponent(0.18)
        bloomShape.fillColor = color.withAlphaComponent(0.6)
        bloomShape.strokeColor = color.withAlphaComponent(0.25)
        lightNode.falloff = 0.8
        lightNode.ambientColor = color.withAlphaComponent(0.15)
        lightNode.lightColor = color.withAlphaComponent(0.95)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func startMotion() {
        startGlowShimmer()
    }
    
    override func updateLayout(using transform: NormalizedLayoutTransform) {
        let thickness = max(transform.length(from: thicknessScale), 1)
        let startPoint = transform.point(from: spec.start)
        let endPoint = transform.point(from: spec.end)
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = hypot(dx, dy)
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        beam.path = CGPath(
            roundedRect: rect,
            cornerWidth: thickness / 2,
            cornerHeight: thickness / 2,
            transform: nil
        )
        beam.position = .zero
        beam.glowWidth = thickness * 2.0
        let glowRect = rect.insetBy(dx: -thickness * 0.9, dy: -thickness * 0.9)
        glowShell.path = CGPath(roundedRect: glowRect, cornerWidth: thickness * 1.25, cornerHeight: thickness * 1.25, transform: nil)
        glowShell.lineWidth = 0
        glowShell.position = .zero
        bloomShape.path = beam.path
        bloomShape.position = beam.position
        let blurRadius = max(thickness * 1.3, 6)
        updateBloomFilter(radius: blurRadius)
        bloomNode.position = .zero
        lightNode.position = .zero
        position = CGPoint(x: (startPoint.x + endPoint.x) / 2, y: (startPoint.y + endPoint.y) / 2)
        zRotation = atan2(dy, dx)
    }
    
    override func didActivateLaser() {
        if glowShell.action(forKey: "segmentGlow") == nil {
            startGlowShimmer()
        }
    }
    
    private func startGlowShimmer() {
        glowShell.removeAction(forKey: "segmentGlow")
        let duration = Double.random(in: 0.9...1.2)
        let up = SKAction.group([
            SKAction.fadeAlpha(to: 0.7, duration: duration),
            SKAction.scaleX(to: 1.05, duration: duration),
            SKAction.scaleY(to: 1.04, duration: duration)
        ])
        let down = SKAction.group([
            SKAction.fadeAlpha(to: 0.35, duration: duration),
            SKAction.scaleX(to: 1.0, duration: duration),
            SKAction.scaleY(to: 1.0, duration: duration)
        ])
        glowShell.run(SKAction.repeatForever(SKAction.sequence([up, down])), withKey: "segmentGlow")
        lightNode.removeAction(forKey: "segmentLight")
        let lightSequence = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.85, duration: duration),
            SKAction.fadeAlpha(to: 0.45, duration: duration)
        ])
        lightNode.run(SKAction.repeatForever(lightSequence), withKey: "segmentLight")
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(other.x - x, other.y - y)
    }
    
    func interpolated(to other: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
    }
}

private struct Capsule {
    let a: CGPoint
    let b: CGPoint
    let radius: CGFloat
    
    func intersectsAny(_ polygons: [Polygon]) -> Bool {
        polygons.contains { intersects($0) }
    }
    
    private func intersects(_ polygon: Polygon) -> Bool {
        let mid = CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
        if polygon.contains(a) || polygon.contains(b) || polygon.contains(mid) {
            return true
        }
        let radiusSquared = radius * radius
        for edge in polygon.edges {
            if segmentDistanceSquared(a, b, edge.0, edge.1) <= radiusSquared {
                return true
            }
        }
        for vertex in polygon.points {
            if distancePointToSegmentSquared(vertex, a, b) <= radiusSquared {
                return true
            }
        }
        return false
    }
    
    private func segmentDistanceSquared(_ a1: CGPoint, _ a2: CGPoint, _ b1: CGPoint, _ b2: CGPoint) -> CGFloat {
        if segmentsIntersect(a1, a2, b1, b2) { return 0 }
        return min(
            distancePointToSegmentSquared(a1, b1, b2),
            distancePointToSegmentSquared(a2, b1, b2),
            distancePointToSegmentSquared(b1, a1, a2),
            distancePointToSegmentSquared(b2, a1, a2)
        )
    }
    
    private func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ q1: CGPoint, _ q2: CGPoint) -> Bool {
        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)
        if o1 != o2 && o3 != o4 { return true }
        if o1 == 0 && onSegment(p1, q1, p2) { return true }
        if o2 == 0 && onSegment(p1, q2, p2) { return true }
        if o3 == 0 && onSegment(q1, p1, q2) { return true }
        if o4 == 0 && onSegment(q1, p2, q2) { return true }
        return false
    }
    
    private func orientation(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Int {
        let val = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
        if abs(val) < .ulpOfOne { return 0 }
        return val > 0 ? 1 : 2
    }
    
    private func onSegment(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Bool {
        q.x <= max(p.x, r.x) + .ulpOfOne && q.x + .ulpOfOne >= min(p.x, r.x) &&
        q.y <= max(p.y, r.y) + .ulpOfOne && q.y + .ulpOfOne >= min(p.y, r.y)
    }
    
    private func distancePointToSegmentSquared(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        if a == b { return point.distance(to: a) * point.distance(to: a) }
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

private struct Polygon {
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
}
