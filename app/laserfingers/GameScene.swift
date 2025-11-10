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
    
    private var buttonNode: ChargeButtonNode?
    private var lasers: [LaserEmitterNode] = []
    private var fingerSprites: [UITouch: FingerSprite] = [:]
    private var progress: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0
    
    private let fillRate: CGFloat
    private let drainRate: CGFloat = 0.18
    private let zapCooldown: TimeInterval = 0.45
    
    init(level: Level, session: GameSession, settings: GameSettings) {
        self.level = level
        self.session = session
        self.settings = settings
        self.fillRate = 0.18 + CGFloat(level.difficulty) * 0.025
        super.init(size: CGSize(width: 1920, height: 1080))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 8/255, green: 9/255, blue: 20/255, alpha: 1)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        if buttonNode == nil {
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
        addBackground()
        addButton()
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
    
    private func addButton() {
        let diameter = min(size.width, size.height) * 0.28
        let button = ChargeButtonNode(diameter: diameter)
        button.position = CGPoint(x: frame.midX, y: frame.midY)
        button.zPosition = 5
        addChild(button)
        buttonNode = button
    }
    
    private func spawnLasers() {
        lasers.forEach { $0.removeFromParent() }
        lasers.removeAll()
        
        let count = max(1, min(4, level.difficulty))
        for index in 0..<count {
            let orientation: LaserEmitterNode.Orientation
            switch (index + level.difficulty) % 3 {
            case 0: orientation = .horizontal
            case 1: orientation = .vertical
            default: orientation = .diagonal
            }
            let thickness: CGFloat = CGFloat(14 + (index * 3))
            let length: CGFloat = orientation == .horizontal ? size.width * 1.4 : size.height * 1.4
            let travel = min(size.width, size.height) * (orientation == .diagonal ? 0.25 : 0.35)
            let color = SKColor(hue: 0.9 - CGFloat(index) * 0.1, saturation: 0.85, brightness: 1, alpha: 0.75)
            let node = LaserEmitterNode(
                orientation: orientation,
                length: length,
                thickness: thickness,
                travel: travel,
                duration: 2.4 + Double(index) * 0.45,
                color: color
            )
            node.position = defaultLaserPosition(for: orientation, index: index, total: count)
            addChild(node)
            node.startAnimating(phase: Double(index) * 0.35)
            lasers.append(node)
        }
    }
    
    private func defaultLaserPosition(for orientation: LaserEmitterNode.Orientation, index: Int, total: Int) -> CGPoint {
        let fraction = CGFloat(index + 1) / CGFloat(total + 1)
        switch orientation {
        case .horizontal:
            return CGPoint(x: frame.midX, y: frame.minY + fraction * frame.height)
        case .vertical:
            return CGPoint(x: frame.minX + fraction * frame.width, y: frame.midY)
        case .diagonal:
            return CGPoint(x: frame.midX, y: frame.midY)
        }
    }
    
    private func layoutScene() {
        buttonNode?.position = CGPoint(x: frame.midX, y: frame.midY)
    }
    
    // MARK: - Touch Handling
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard session.status == .running else { return }
        for touch in touches {
            guard fingerSprites.count < max(1, session.touchAllowance) else { continue }
            let location = touch.location(in: self)
            let sprite = makeFingerSprite(at: location)
            addChild(sprite.node)
            var data = FingerSprite(node: sprite.node, isPressingButton: isTouchOnButton(location), lastZapTime: 0)
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
            sprite.isPressingButton = isTouchOnButton(location)
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
    
    private func makeFingerSprite(at point: CGPoint) -> FingerSprite {
        let radius: CGFloat = 22
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = SKColor.white.withAlphaComponent(0.25)
        node.strokeColor = SKColor.white.withAlphaComponent(0.45)
        node.lineWidth = 2
        node.position = point
        node.zPosition = 20
        node.glowWidth = 4
        return FingerSprite(node: node, isPressingButton: false, lastZapTime: 0)
    }
    
    private func isTouchOnButton(_ point: CGPoint) -> Bool {
        guard let buttonNode else { return false }
        return buttonNode.contains(point, in: self)
    }
    
    // MARK: - Game Loop
    
    override func update(_ currentTime: TimeInterval) {
        guard session.status == .running else { return }
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let delta = min(currentTime - lastUpdateTime, 1 / 20)
        lastUpdateTime = currentTime
        
        let pressingCount = fingerSprites.reduce(0) { partialResult, entry in
            partialResult + (entry.value.isPressingButton ? 1 : 0)
        }
        buttonNode?.updatePressIntensity(pressingCount: pressingCount, maxTouches: max(1, session.touchAllowance))
        
        if pressingCount > 0 {
            progress += fillRate * CGFloat(delta)
        } else {
            progress -= drainRate * CGFloat(delta)
        }
        progress = progress.clamped(to: 0...1)
        buttonNode?.updateProgress(progress)
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
        buttonNode?.celebrate()
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

// MARK: - Menu Background

final class MenuBackgroundScene: SKScene {
    private var lasers: [LaserEmitterNode] = []
    
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
            let orientation: LaserEmitterNode.Orientation = index % 2 == 0 ? .horizontal : .vertical
            let node = LaserEmitterNode(
                orientation: orientation,
                length: orientation == .horizontal ? size.width * 1.3 : size.height * 1.3,
                thickness: 18,
                travel: min(size.width, size.height) * 0.4,
                duration: 4 + Double(index),
                color: SKColor(hue: 0.85 - CGFloat(index) * 0.1, saturation: 0.7, brightness: 1, alpha: 0.5)
            )
            node.position = CGPoint(x: frame.midX, y: frame.midY)
            addChild(node)
            node.startAnimating(phase: Double(index) * 0.8)
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
    var isPressingButton: Bool
    var lastZapTime: TimeInterval
}

private final class ChargeButtonNode: SKNode {
    private let outline: SKShapeNode
    private let fillNode: SKShapeNode
    private let glowNode: SKShapeNode
    private let radius: CGFloat
    
    init(diameter: CGFloat) {
        self.radius = diameter / 2
        outline = SKShapeNode(circleOfRadius: diameter / 2)
        outline.lineWidth = 6
        outline.strokeColor = SKColor.white.withAlphaComponent(0.7)
        outline.fillColor = SKColor.black.withAlphaComponent(0.4)
        
        fillNode = SKShapeNode(circleOfRadius: diameter * 0.35)
        fillNode.fillColor = SKColor.systemGreen
        fillNode.strokeColor = .clear
        fillNode.yScale = 0
        
        glowNode = SKShapeNode(circleOfRadius: diameter * 0.4)
        glowNode.fillColor = SKColor.systemPink.withAlphaComponent(0.3)
        glowNode.strokeColor = .clear
        glowNode.alpha = 0.1
        
        super.init()
        addChild(glowNode)
        addChild(outline)
        addChild(fillNode)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateProgress(_ progress: CGFloat) {
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
}

private final class LaserEmitterNode: SKNode {
    enum Orientation {
        case horizontal
        case vertical
        case diagonal
    }
    
    private let orientation: Orientation
    private let travel: CGFloat
    private let duration: TimeInterval
    private let beam: SKShapeNode
    
    init(orientation: Orientation, length: CGFloat, thickness: CGFloat, travel: CGFloat, duration: TimeInterval, color: SKColor) {
        self.orientation = orientation
        self.travel = travel
        self.duration = duration
        let size = orientation == .horizontal
            ? CGSize(width: length, height: thickness)
            : CGSize(width: thickness, height: length)
        beam = SKShapeNode(rectOf: size, cornerRadius: thickness / 2)
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.8)
        beam.glowWidth = thickness * 0.8
        super.init()
        if orientation == .diagonal {
            beam.zRotation = .pi / 4
            beam.xScale = 1.2
            beam.yScale = 1.2
        }
        addChild(beam)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func startAnimating(phase: TimeInterval = 0) {
        let vector = movementVector()
        let forward = SKAction.moveBy(x: vector.dx, y: vector.dy, duration: duration / 2)
        let backward = forward.reversed()
        let loop = SKAction.sequence([forward, backward])
        let delayedLoop = SKAction.sequence([SKAction.wait(forDuration: phase), SKAction.repeatForever(loop)])
        run(delayedLoop, withKey: "patrol")
    }
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    private func movementVector() -> CGVector {
        switch orientation {
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
