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
    
    private var buttonNodes: [ChargeButtonNode] = []
    private var lasers: [LaserNode] = []
    private var fingerSprites: [UITouch: FingerSprite] = [:]
    private var progress: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0
    
    private let fallbackChargeRate: CGFloat
    private let drainRate: CGFloat = 0.18
    private let zapCooldown: TimeInterval = 0.45
    
    init(level: Level, session: GameSession, settings: GameSettings) {
        self.level = level
        self.session = session
        self.settings = settings
        let averageDuration = max(CGFloat(level.averageChargeDuration), 0.25)
        self.fallbackChargeRate = 1.0 / averageDuration
        super.init(size: CGSize(width: 1920, height: 1080))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 8/255, green: 9/255, blue: 20/255, alpha: 1)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        if buttonNodes.isEmpty {
            buildScene()
        }
        session.status = .running
        isUserInteractionEnabled = true
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutScene()
    }
    
    private func buildScene() {
        removeAllChildren()
        fingerSprites.removeAll()
        progress = 0
        session.fillPercentage = 0
        addBackground()
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
    
    private func addButtons() {
        buttonNodes.forEach { $0.removeFromParent() }
        buttonNodes.removeAll()
        
        let specs = level.buttons.isEmpty ? [
            Level.Button(
                id: "core",
                shape: .circle,
                position: .init(x: 0.5, y: 0.5),
                size: 0.25,
                fillColor: "#FF2E89",
                glowColor: "#FF7FC0",
                rimColor: "#FFFFFF",
                timeToFull: 3.0
            )
        ] : level.buttons
        
        let reference = min(size.width, size.height)
        buttonNodes = specs.map { spec in
            let node = ChargeButtonNode(spec: spec, referenceLength: reference)
            node.position = point(for: spec.position)
            node.zPosition = 5
            node.updateChargeProgress(progress)
            addChild(node)
            return node
        }
    }
    
    private func spawnLasers() {
        lasers.forEach { $0.removeFromParent() }
        lasers.removeAll()
        
        guard !level.lasers.isEmpty else {
            spawnLegacyLasers()
            return
        }
        
        for (index, spec) in level.lasers.enumerated() {
            guard let node = makeLaserNode(from: spec) else { continue }
            addChild(node)
            node.activate(phase: spec.phase ?? Double(index) * 0.35)
            lasers.append(node)
        }
    }
    
    private func spawnLegacyLasers() {
        let count = max(1, min(4, level.difficulty))
        for index in 0..<count {
            let axis: Level.Laser.Axis
            switch (index + level.difficulty) % 3 {
            case 0: axis = .horizontal
            case 1: axis = .vertical
            default: axis = .diagonal
            }
            let color = SKColor(hue: 0.9 - CGFloat(index) * 0.1, saturation: 0.85, brightness: 1, alpha: 0.75)
            let node = SweepingLaserNode(
                axis: axis,
                length: sweepLength(for: axis),
                thickness: min(size.width, size.height) * 0.015,
                travel: min(size.width, size.height) * (axis == .diagonal ? 0.25 : 0.35),
                duration: 2.4 + Double(index) * 0.45,
                color: color
            )
            node.position = sweepPosition(for: axis, offset: CGFloat(index + 1) / CGFloat(count + 1))
            addChild(node)
            node.activate(phase: Double(index) * 0.35)
            lasers.append(node)
        }
    }
    
    private func makeLaserNode(from spec: Level.Laser) -> LaserNode? {
        let color = SKColor.fromHex(spec.color, alpha: 0.75)
        let minDimension = min(size.width, size.height)
        switch spec.type {
        case .sweep:
            let axis = spec.axis ?? .horizontal
            let node = SweepingLaserNode(
                axis: axis,
                length: sweepLength(for: axis),
                thickness: max(spec.thickness, 0.01) * minDimension,
                travel: max(spec.travel ?? 0.25, 0.05) * minDimension,
                duration: max(spec.speed, 0.4),
                color: color
            )
            node.position = sweepPosition(for: axis, offset: spec.offset ?? 0.5)
            return node
        case .rotate:
            guard let center = spec.center else { return nil }
            let node = RotatingLaserNode(
                radius: max(spec.radius ?? 0.3, 0.1) * minDimension,
                thickness: max(spec.thickness, 0.01) * minDimension,
                duration: max(spec.speed, 0.4),
                color: color,
                clockwise: spec.direction != .counterclockwise
            )
            node.position = point(for: center)
            return node
        }
    }
    
    private func sweepLength(for axis: Level.Laser.Axis) -> CGFloat {
        switch axis {
        case .horizontal:
            return size.width * 1.4
        case .vertical:
            return size.height * 1.4
        case .diagonal:
            return hypot(size.width, size.height)
        }
    }
    
    private func sweepPosition(for axis: Level.Laser.Axis, offset: CGFloat) -> CGPoint {
        let fraction = offset.clamped(to: 0...1)
        switch axis {
        case .horizontal:
            return CGPoint(x: frame.midX, y: frame.minY + fraction * frame.height)
        case .vertical:
            return CGPoint(x: frame.minX + fraction * frame.width, y: frame.midY)
        case .diagonal:
            return CGPoint(x: frame.midX, y: frame.midY)
        }
    }
    
    private func point(for coordinate: Level.Coordinate) -> CGPoint {
        CGPoint(
            x: frame.minX + coordinate.x.clamped(to: 0...1) * frame.width,
            y: frame.minY + coordinate.y.clamped(to: 0...1) * frame.height
        )
    }
    
    private func layoutScene() {
        for button in buttonNodes {
            button.position = point(for: button.spec.position)
        }
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.status == .running else { return }
        for touch in touches {
            guard fingerSprites.count < max(1, session.touchAllowance) else { continue }
            let location = touch.location(in: self)
            let node = makeFingerSprite(at: location)
            addChild(node)
            var data = FingerSprite(node: node, activeButton: button(at: location), lastZapTime: 0)
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
            sprite.activeButton = button(at: location)
            fingerSprites[touch] = sprite
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        removeTouches(touches)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
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
    
    private func button(at point: CGPoint) -> ChargeButtonNode? {
        buttonNodes.first { $0.contains(point, in: self) }
    }
    
    // MARK: - Game Loop
    
    override func update(_ currentTime: TimeInterval) {
        guard session.status == .running else { return }
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = min(currentTime - lastUpdateTime, 1 / 20)
        lastUpdateTime = currentTime
        
        let pressingCount = fingerSprites.values.reduce(0) { partialResult, sprite in
            partialResult + (sprite.activeButton == nil ? 0 : 1)
        }
        
        var totalChargeRate: CGFloat = fingerSprites.values.reduce(0) { partialResult, sprite in
            guard let button = sprite.activeButton else { return partialResult }
            return partialResult + button.chargeRate
        }
        if totalChargeRate == 0, pressingCount > 0 {
            totalChargeRate = fallbackChargeRate
        }
        
        if totalChargeRate > 0 {
            progress += totalChargeRate * CGFloat(delta)
        } else {
            progress -= drainRate * CGFloat(delta)
        }
        progress = progress.clamped(to: 0...1)
        for button in buttonNodes {
            let presses = fingerSprites.values.filter { $0.activeButton === button }.count
            button.updatePressIntensity(pressingCount: presses, maxTouches: max(1, session.touchAllowance))
            button.updateChargeProgress(progress)
        }
        session.fillPercentage = progress
        
        checkLaserHits(currentTime: currentTime)
        
        if progress >= 1 {
            completeLevel()
        }
    }
    
    private func checkLaserHits(currentTime: TimeInterval) {
        for (touch, sprite) in fingerSprites {
            guard currentTime - sprite.lastZapTime > zapCooldown else { continue }
            let position = sprite.node.position
            if lasers.contains(where: { $0.isDangerous(at: position, in: self) }) {
                registerZap(for: touch, currentTime: currentTime)
            }
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
            failLevel()
        }
    }
    
    private func completeLevel() {
        guard session.status == .running else { return }
        session.status = .won
        isUserInteractionEnabled = false
        buttonNodes.forEach { $0.celebrate() }
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
    func activate(phase: TimeInterval)
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
    
    private func setup() {
        let gradient = SKShapeNode(rectOf: CGSize(width: size.width * 1.1, height: size.height * 1.1), cornerRadius: 48)
        gradient.fillColor = SKColor(red: 0.05, green: 0, blue: 0.1, alpha: 0.6)
        gradient.strokeColor = .clear
        gradient.zPosition = -5
        addChild(gradient)
        
        lasers = (0..<3).map { index in
            let axis: Level.Laser.Axis = index % 2 == 0 ? .horizontal : .vertical
            let node = SweepingLaserNode(
                axis: axis,
                length: axis == .horizontal ? size.width * 1.3 : size.height * 1.3,
                thickness: 18,
                travel: min(size.width, size.height) * 0.4,
                duration: 4 + Double(index),
                color: SKColor(hue: 0.85 - CGFloat(index) * 0.1, saturation: 0.7, brightness: 1, alpha: 0.5)
            )
            node.position = CGPoint(x: frame.midX, y: frame.midY)
            addChild(node)
            node.activate(phase: Double(index) * 0.8)
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
    var activeButton: ChargeButtonNode?
    var lastZapTime: TimeInterval
}

private final class ChargeButtonNode: SKNode {
    private let outline: SKShapeNode
    private let fillNode: SKShapeNode
    private let glowNode: SKShapeNode
    let spec: Level.Button
    let chargeRate: CGFloat
    
    init(spec: Level.Button, referenceLength: CGFloat) {
        self.spec = spec
        let size = max(spec.size, 0.1) * referenceLength
        outline = ChargeButtonNode.makeShape(shape: spec.shape, size: size, inset: 0)
        fillNode = ChargeButtonNode.makeShape(shape: spec.shape, size: size * 0.55, inset: 0)
        glowNode = ChargeButtonNode.makeShape(shape: spec.shape, size: size * 1.05, inset: 0)
        chargeRate = 1.0 / CGFloat(max(spec.timeToFull, 0.15))
        super.init()
        outline.lineWidth = size * 0.04
        outline.strokeColor = SKColor.fromHex(spec.rimColor ?? "#FFFFFF", alpha: 0.8)
        outline.fillColor = SKColor.black.withAlphaComponent(0.45)
        
        fillNode.fillColor = SKColor.fromHex(spec.fillColor)
        fillNode.strokeColor = .clear
        fillNode.yScale = 0
        
        glowNode.fillColor = SKColor.fromHex(spec.glowColor ?? spec.fillColor, alpha: 0.35)
        glowNode.strokeColor = .clear
        glowNode.alpha = 0.1
        
        addChild(glowNode)
        addChild(outline)
        addChild(fillNode)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateChargeProgress(_ progress: CGFloat) {
        fillNode.yScale = progress
        fillNode.alpha = 0.6 + 0.4 * progress
    }
    
    func updatePressIntensity(pressingCount: Int, maxTouches: Int) {
        let fraction = CGFloat(pressingCount) / CGFloat(max(1, maxTouches))
        glowNode.alpha = 0.1 + fraction * 0.6
    }
    
    func celebrate() {
        let pulse = SKAction.scale(to: 1.08, duration: 0.15)
        let reverse = SKAction.scale(to: 1.0, duration: 0.15)
        run(SKAction.sequence([pulse, reverse]))
    }
    
    func contains(_ point: CGPoint, in scene: SKScene) -> Bool {
        let local = convert(point, from: scene)
        return outline.contains(local)
    }
    
    private static func makeShape(shape: Level.Button.Shape, size: CGFloat, inset: CGFloat) -> SKShapeNode {
        switch shape {
        case .circle:
            return SKShapeNode(circleOfRadius: max(size - inset, 2) / 2)
        case .square:
            let edge = max(size - inset, 4)
            return SKShapeNode(rectOf: CGSize(width: edge, height: edge), cornerRadius: edge * 0.12)
        case .capsule:
            let width = max(size - inset, 4)
            let height = width * 0.55
            return SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2)
        }
    }
}

private final class SweepingLaserNode: SKNode, LaserObstacle {
    private let axis: Level.Laser.Axis
    private let travel: CGFloat
    private let duration: TimeInterval
    private let beam: SKShapeNode
    
    init(axis: Level.Laser.Axis, length: CGFloat, thickness: CGFloat, travel: CGFloat, duration: TimeInterval, color: SKColor) {
        self.axis = axis
        self.travel = travel
        self.duration = duration
        let size: CGSize
        switch axis {
        case .horizontal:
            size = CGSize(width: length, height: thickness)
        case .vertical:
            size = CGSize(width: thickness, height: length)
        case .diagonal:
            size = CGSize(width: length, height: thickness)
        }
        beam = SKShapeNode(rectOf: size, cornerRadius: thickness / 2)
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.8)
        beam.glowWidth = thickness * 0.8
        super.init()
        if axis == .diagonal {
            beam.zRotation = .pi / 4
        }
        addChild(beam)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func activate(phase: TimeInterval = 0) {
        let vector = movementVector()
        let forward = SKAction.moveBy(x: vector.dx, y: vector.dy, duration: duration / 2)
        let backward = forward.reversed()
        let loop = SKAction.sequence([forward, backward])
        let start = SKAction.wait(forDuration: max(phase, 0))
        run(SKAction.sequence([start, SKAction.repeatForever(loop)]), withKey: "patrol")
    }
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    private func movementVector() -> CGVector {
        switch axis {
        case .horizontal:
            return CGVector(dx: 0, dy: travel)
        case .vertical:
            return CGVector(dx: travel, dy: 0)
        case .diagonal:
            let component = travel / sqrt(2)
            return CGVector(dx: component, dy: component)
        }
    }
}

private final class RotatingLaserNode: SKNode, LaserObstacle {
    private let beam: SKShapeNode
    private let duration: TimeInterval
    private let clockwise: Bool
    
    init(radius: CGFloat, thickness: CGFloat, duration: TimeInterval, color: SKColor, clockwise: Bool) {
        self.duration = duration
        self.clockwise = clockwise
        beam = SKShapeNode(rectOf: CGSize(width: thickness, height: radius), cornerRadius: thickness / 2)
        beam.position = CGPoint(x: 0, y: radius / 2)
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.8)
        beam.glowWidth = thickness * 0.9
        super.init()
        addChild(beam)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func activate(phase: TimeInterval = 0) {
        let direction: CGFloat = clockwise ? -1 : 1
        let normalizedPhase = CGFloat((phase / duration).truncatingRemainder(dividingBy: 1))
        zRotation = direction * normalizedPhase * (.pi * 2)
        let rotation = SKAction.rotate(byAngle: direction * (.pi * 2), duration: duration)
        run(SKAction.repeatForever(rotation), withKey: "spin")
    }
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
