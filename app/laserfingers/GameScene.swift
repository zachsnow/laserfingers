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
    private var buttonNodeMap: [String: ChargeButtonNode] = [:]
    private var buttonClusterStates: [ButtonClusterState] = []
    private var buttonClusterMembership: [String: [Int]] = [:]
    private var lasers: [LaserNode] = []
    private var laserNodesById: [String: LaserNode] = [:]
    private var fingerSprites: [UITouch: FingerSprite] = [:]
    private var lastUpdateTime: TimeInterval = 0
    
    private let drainRate: CGFloat = 0.18
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
        session.fillPercentage = 0
        addBackground()
        addButtons()
        spawnLasers()
        wireButtonControls()
        buttonNodes.forEach { $0.resetState() }
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
        buttonNodeMap.removeAll()
        
        let setSpecs = level.resolvedButtonSets
        let reference = min(size.width, size.height)

        buttonNodes = setSpecs.flatMap { set -> [ChargeButtonNode] in
            set.pads.map { pad in
                let node = ChargeButtonNode(pad: pad, set: set, referenceLength: reference)
                node.position = point(for: pad.position)
                node.zPosition = 5
                addChild(node)
                buttonNodeMap[pad.id] = node
                return node
            }
        }
        configureButtonClusters(with: setSpecs)
    }
    
    private func spawnLasers() {
        lasers.forEach { $0.removeFromParent() }
        lasers.removeAll()
        laserNodesById.removeAll()
        
        guard !level.lasers.isEmpty else {
            spawnLegacyLasers()
            return
        }
        
        for (index, spec) in level.lasers.enumerated() {
            guard let node = makeLaserNode(from: spec) else { continue }
            addChild(node)
            node.activate(phase: spec.phase ?? Double(index) * 0.35)
            lasers.append(node)
            laserNodesById[spec.id] = node
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
            let radius = max(spec.radius ?? 0.3, 0.1) * minDimension
            let armLength = radius + max(size.width, size.height)
            let node = RotatingLaserNode(
                armLength: armLength,
                thickness: max(spec.thickness, 0.01) * minDimension,
                duration: max(spec.speed, 0.4),
                color: color,
                clockwise: spec.direction != .counterclockwise
            )
            node.position = point(for: center)
            return node
        case .segment:
            guard
                let start = spec.startPoint,
                let end = spec.endPoint
            else { return nil }
            let togglePeriod = spec.togglePeriod.flatMap { $0 > 0 ? $0 : nil }
            let node = SegmentLaserNode(
                start: point(for: start),
                end: point(for: end),
                thickness: max(spec.thickness, 0.01) * minDimension,
                color: color,
                togglePeriod: togglePeriod
            )
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
    
    private func configureButtonClusters(with sets: [Level.ButtonSet]) {
        buttonClusterStates.removeAll()
        buttonClusterMembership.removeAll()
        
        for spec in sets {
            let nodes = spec.pads.compactMap { buttonNodeMap[$0.id] }
            guard !nodes.isEmpty else { continue }
            let chargeRate = (1.0 / CGFloat(max(spec.timeToFull, 0.1))) * 1.5
            let state = ButtonClusterState(
                id: spec.id,
                mode: ButtonClusterState.Mode(from: spec.mode),
                nodes: nodes,
                progress: 0,
                chargeRate: chargeRate,
                required: spec.required ?? true
            )
            let clusterIndex = buttonClusterStates.count
            buttonClusterStates.append(state)
            for node in nodes {
                buttonClusterMembership[node.id, default: []].append(clusterIndex)
            }
        }
        
        if buttonClusterStates.isEmpty {
            for node in buttonNodes {
                let chargeRate = (1.0 / CGFloat(max(node.timeToFull, 0.1))) * 1.5
                let state = ButtonClusterState(
                    id: "auto-\(node.id)",
                    mode: .any,
                    nodes: [node],
                    progress: 0,
                    chargeRate: chargeRate,
                    required: node.participatesInWin()
                )
                let index = buttonClusterStates.count
                buttonClusterStates.append(state)
                buttonClusterMembership[node.id, default: []].append(index)
            }
        }
    }
    
    private func wireButtonControls() {
        for node in buttonNodes {
            guard let laserId = node.controlsLaserId else { continue }
            node.controlCallback = { [weak self] suppressed in
                self?.laserNodesById[laserId]?.setSuppressed(suppressed)
            }
            if let laser = laserNodesById[laserId] {
                laser.setSuppressed(node.controlActiveState())
            }
        }
    }
    
    private func layoutScene() {
        for button in buttonNodes {
            button.position = point(for: button.pad.position)
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
        
        let pressCounts = fingerSprites.values.reduce(into: [ObjectIdentifier: Int]()) { partial, sprite in
            guard let button = sprite.activeButton else { return }
            partial[ObjectIdentifier(button), default: 0] += 1
        }
        
        let maxTouches = max(1, session.touchAllowance)
        let isButtonActive: (ChargeButtonNode) -> Bool = { button in
            let count = pressCounts[ObjectIdentifier(button)] ?? 0
            return button.isActive(pressCount: count)
        }
        
        for button in buttonNodes {
            let count = pressCounts[ObjectIdentifier(button)] ?? 0
            button.updatePressIntensity(pressingCount: count, maxTouches: maxTouches)
        }
        
        for index in buttonClusterStates.indices {
            var state = buttonClusterStates[index]
            let active: Bool
            switch state.mode {
            case .any:
                active = state.nodes.contains { isButtonActive($0) }
            case .all:
                active = !state.nodes.isEmpty && state.nodes.allSatisfy { isButtonActive($0) }
            }
            if active {
                state.progress += state.chargeRate * CGFloat(delta)
            } else {
                state.progress -= drainRate * CGFloat(delta)
            }
            state.progress = state.progress.clamped(to: 0...1)
            buttonClusterStates[index] = state
        }
        
        for node in buttonNodes {
            let memberships = buttonClusterMembership[node.id]?.map { buttonClusterStates[$0].progress } ?? []
            let display = memberships.max() ?? 0
            node.setDisplayProgress(display)
        }
        
        let requiredClusters = buttonClusterStates.filter { $0.required }
        let clustersForFill = requiredClusters.isEmpty ? buttonClusterStates : requiredClusters
        let averageProgress: CGFloat
        if clustersForFill.isEmpty {
            averageProgress = 0
        } else {
            let totalProgress = clustersForFill.reduce(CGFloat(0)) { $0 + $1.progress }
            averageProgress = totalProgress / CGFloat(clustersForFill.count)
        }
        session.fillPercentage = averageProgress
        
        checkLaserHits(currentTime: currentTime)
        
        if !clustersForFill.isEmpty && clustersForFill.allSatisfy({ $0.progress >= 1 }) {
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
    func setSuppressed(_ suppressed: Bool)
}

extension LaserObstacle {
    func setSuppressed(_ suppressed: Bool) {}
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

private struct ButtonClusterState {
    enum Mode {
        case any
        case all
        
        init(from spec: Level.ButtonCluster.Mode) {
            switch spec {
            case .any: self = .any
            case .all: self = .all
            }
        }
        
        init(from spec: Level.ButtonSet.Mode) {
            switch spec {
            case .any: self = .any
            case .all: self = .all
            }
        }
    }
    
    let id: String
    let mode: Mode
    let nodes: [ChargeButtonNode]
    var progress: CGFloat
    let chargeRate: CGFloat
    let required: Bool
}

private final class ChargeButtonNode: SKNode {
    private let outline: SKShapeNode
    private let fillNode: SKShapeNode
    private let glowNode: SKShapeNode
    let id: String
    let pad: Level.ButtonPad
    let controlsLaserId: String?
    let requiredForWin: Bool
    let timeToFull: Double
    private let isSwitch: Bool
    private let locksOnFill: Bool
    private(set) var isLocked: Bool = false
    private var displayProgress: CGFloat = 0
    private var controlState: Bool = false
    var controlCallback: ((Bool) -> Void)?
    
    init(pad: Level.ButtonPad, set: Level.ButtonSet, referenceLength: CGFloat) {
        self.id = pad.id
        self.pad = pad
        self.controlsLaserId = set.controls
        self.requiredForWin = set.required ?? true
        self.timeToFull = set.timeToFull
        self.isSwitch = (set.kind ?? .charge) == .switch
        let drainer = (set.isDrainer ?? false) || self.isSwitch
        self.locksOnFill = !drainer && !self.isSwitch
        let size = max(pad.size, 0.1) * referenceLength
        outline = ChargeButtonNode.makeOutline(shape: pad.shape, size: size, inset: 0, isDrainer: drainer)
        fillNode = ChargeButtonNode.makeShape(shape: pad.shape, size: max(size * 0.92, size * 0.3), inset: 0)
        glowNode = ChargeButtonNode.makeShape(shape: pad.shape, size: size * 1.05, inset: 0)
        super.init()
        outline.lineWidth = size * 0.04
        outline.strokeColor = SKColor.fromHex(set.rimColor ?? "#FFFFFF", alpha: 0.8)
        outline.fillColor = SKColor.black.withAlphaComponent(0.45)
        
        fillNode.fillColor = SKColor.fromHex(set.fillColor)
        fillNode.strokeColor = .clear
        fillNode.setScale(0.05)
        
        glowNode.fillColor = SKColor.fromHex(set.glowColor ?? set.fillColor, alpha: 0.35)
        glowNode.strokeColor = .clear
        glowNode.alpha = 0.1
        
        addChild(glowNode)
        addChild(outline)
        addChild(fillNode)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func resetState() {
        isLocked = false
        controlState = false
        controlCallback?(false)
        setDisplayProgress(0)
    }
    
    func setDisplayProgress(_ progress: CGFloat) {
        displayProgress = progress.clamped(to: 0...1)
        if locksOnFill && !isLocked && displayProgress >= 0.999 {
            isLocked = true
            displayProgress = 1.0
        } else if isLocked {
            displayProgress = 1.0
        } else if isSwitch {
            isLocked = false
        }
        let scale = max(displayProgress, 0.05)
        fillNode.xScale = scale
        fillNode.yScale = scale
        fillNode.alpha = 0.6 + 0.4 * displayProgress
        let controlActive = displayProgress >= 0.999
        updateControlState(controlActive)
    }
    
    func isActive(pressCount: Int) -> Bool {
        if isSwitch {
            return pressCount > 0
        }
        return pressCount > 0 || isLocked
    }
    
    func updatePressIntensity(pressingCount: Int, maxTouches: Int) {
        let fraction = CGFloat(pressingCount) / CGFloat(max(1, maxTouches))
        glowNode.alpha = 0.1 + fraction * 0.6
    }
    
    func celebrate() {
        guard !isSwitch else { return }
        let pulse = SKAction.scale(to: 1.08, duration: 0.15)
        let reverse = SKAction.scale(to: 1.0, duration: 0.15)
        run(SKAction.sequence([pulse, reverse]))
    }
    
    func contains(_ point: CGPoint, in scene: SKScene) -> Bool {
        let local = convert(point, from: scene)
        return outline.contains(local)
    }
    
    func participatesInWin() -> Bool {
        requiredForWin && !isSwitch
    }
    
    func controlActiveState() -> Bool {
        controlState
    }
    
    private func updateControlState(_ newValue: Bool) {
        guard controlsLaserId != nil else { return }
        if controlState != newValue {
            controlState = newValue
            controlCallback?(newValue)
        }
    }
    
    private static func makeOutline(shape: Level.ButtonShape, size: CGFloat, inset: CGFloat, isDrainer: Bool) -> SKShapeNode {
        let path = basePath(shape: shape, size: size, inset: inset)
        if isDrainer {
            let dashed = path.copy(dashingWithPhase: 0, lengths: [size * 0.15, size * 0.1])
            return SKShapeNode(path: dashed)
        }
        return SKShapeNode(path: path)
    }
    
    private static func makeShape(shape: Level.ButtonShape, size: CGFloat, inset: CGFloat) -> SKShapeNode {
        let path = basePath(shape: shape, size: size, inset: inset)
        return SKShapeNode(path: path)
    }
    
    private static func basePath(shape: Level.ButtonShape, size: CGFloat, inset: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch shape {
        case .circle:
            let radius = max(size - inset, 2) / 2
            path.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        case .square:
            let edge = max(size - inset, 4)
            path.addRoundedRect(in: CGRect(x: -edge / 2, y: -edge / 2, width: edge, height: edge), cornerWidth: edge * 0.12, cornerHeight: edge * 0.12)
        case .capsule:
            let width = max(size - inset, 4)
            let height = width * 0.55
            path.addRoundedRect(in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height), cornerWidth: height / 2, cornerHeight: height / 2)
        }
        return path.copy() ?? path
    }
}

private final class SweepingLaserNode: SKNode, LaserObstacle {
    private let axis: Level.Laser.Axis
    private let travel: CGFloat
    private let duration: TimeInterval
    private let beam: SKShapeNode
    private var suppressed = false
    
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
        guard !suppressed else { return false }
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    func setSuppressed(_ suppressed: Bool) {
        self.suppressed = suppressed
        let alpha: CGFloat = suppressed ? 0.05 : 1.0
        beam.alpha = alpha
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
    private var suppressed = false
    
    init(armLength: CGFloat, thickness: CGFloat, duration: TimeInterval, color: SKColor, clockwise: Bool) {
        self.duration = duration
        self.clockwise = clockwise
        beam = SKShapeNode(rectOf: CGSize(width: thickness, height: armLength), cornerRadius: thickness / 2)
        beam.position = CGPoint(x: 0, y: armLength / 2)
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
        guard !suppressed else { return false }
        let localPoint = convert(scenePoint, from: scene)
        return beam.contains(localPoint)
    }
    
    func setSuppressed(_ suppressed: Bool) {
        self.suppressed = suppressed
        let alpha: CGFloat = suppressed ? 0.05 : 1.0
        beam.alpha = alpha
    }
}

private final class SegmentLaserNode: SKNode, LaserObstacle {
    private let beam: SKShapeNode
    private let startBox: SKShapeNode
    private let endBox: SKShapeNode
    private let togglePeriod: TimeInterval?
    private var isOn: Bool = true
    private var suppressed = false
    
    init(start: CGPoint, end: CGPoint, thickness: CGFloat, color: SKColor, togglePeriod: Double?) {
        self.togglePeriod = (togglePeriod ?? 0) > 0 ? togglePeriod : nil
        let vector = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let length = hypot(vector.dx, vector.dy)
        beam = SKShapeNode(rectOf: CGSize(width: length, height: thickness), cornerRadius: thickness / 2)
        beam.fillColor = color
        beam.strokeColor = color.withAlphaComponent(0.9)
        beam.glowWidth = thickness * 0.8
        let boxSize = CGSize(width: thickness * 1.4, height: thickness * 1.4)
        startBox = SKShapeNode(rectOf: boxSize, cornerRadius: thickness * 0.2)
        startBox.fillColor = color
        startBox.strokeColor = color.withAlphaComponent(0.9)
        endBox = startBox.copy() as! SKShapeNode
        super.init()
        let angle = atan2(vector.dy, vector.dx)
        beam.zRotation = angle
        beam.position = CGPoint(x: vector.dx / 2, y: vector.dy / 2)
        startBox.position = .zero
        endBox.position = CGPoint(x: vector.dx, y: vector.dy)
        addChild(beam)
        addChild(startBox)
        addChild(endBox)
        position = start
        updateVisualState()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func activate(phase: TimeInterval = 0) {
        guard let period = togglePeriod, period > 0 else {
            updateVisualState()
            return
        }
        let wait = SKAction.wait(forDuration: period)
        let toggle = SKAction.run { [weak self] in
            self?.toggleState()
        }
        let cycle = SKAction.repeatForever(SKAction.sequence([wait, toggle]))
        if phase > 0 {
            run(SKAction.sequence([SKAction.wait(forDuration: phase), cycle]), withKey: "segment-toggle")
        } else {
            run(cycle, withKey: "segment-toggle")
        }
    }
    
    func isDangerous(at scenePoint: CGPoint, in scene: SKScene) -> Bool {
        guard isOn && !suppressed else { return false }
        let local = convert(scenePoint, from: scene)
        return beam.contains(local)
    }
    
    func setSuppressed(_ suppressed: Bool) {
        self.suppressed = suppressed
        updateVisualState()
    }
    
    private func toggleState() {
        isOn.toggle()
        updateVisualState()
    }
    
    private func updateVisualState() {
        let alpha: CGFloat = (isOn && !suppressed) ? 1.0 : 0.05
        beam.alpha = alpha
        startBox.alpha = alpha
        endBox.alpha = alpha
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
