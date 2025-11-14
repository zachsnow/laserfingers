//
//  LaserScenes.swift
//  laserfingers
//
//  Created by Zach Snow on 11/9/25.
//

import Foundation
import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class LaserGameScene: LevelSceneBase {
    private let session: GameSession
    private var fingerSprites: [UITouch: FingerSprite] = [:]
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
        self.session = session
        super.init(level: level, settings: settings)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        session.status = .running
        addAlertOverlay()
        setPlaybackState(.playing)
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        updateAlertOverlayFrame()
    }
    
    override func rebuildScene() {
        super.rebuildScene()
        addAlertOverlay()
        fingerSprites.removeAll()
        session.fillPercentage = 0
    }
    
    override func resetTimeline() {
        super.resetTimeline()
        fingerSprites.values.forEach { sprite in
            sprite.node.removeFromParent()
        }
        fingerSprites.removeAll()
        session.fillPercentage = 0
    }
    
    override func advanceTimeline(delta: TimeInterval, currentTime: TimeInterval) {
        super.advanceTimeline(delta: delta, currentTime: currentTime)
        // Continue animating but ignore button/laser interactions when won/lost
        guard session.status == .running else { return }
        checkLaserHits(currentTime: currentTime)
        evaluateWinCondition()
    }
    
    override func activeTouchPoints() -> [CGPoint] {
        fingerSprites.values.map { $0.node.position }
    }
    
    override func handleButtonEvent(_ event: ButtonEvent) {
        switch event {
        case .turnedOn:
            triggerHaptics(.success)
        case .touchBegan(_), .touchEnded(_), .turnedOff(_):
            break
        }
    }
    
    override func didUpdateFillPercentage(_ value: CGFloat) {
        session.fillPercentage = value
    }
    
    func setScenePaused(_ paused: Bool) {
        setPlaybackState(paused ? .paused : .playing)
        isUserInteractionEnabled = !paused && session.status == .running
    }
    
    private func addAlertOverlay() {
        updateAlertOverlayFrame()
        alertOverlay.removeAllActions()
        alertOverlay.alpha = 0
        if alertOverlay.parent == nil {
            addChild(alertOverlay)
        }
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

private struct FingerSprite {
    static let fingerRadius: CGFloat = 22
    let node: SKShapeNode
    var lastZapTime: TimeInterval
    var previousPosition: CGPoint
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
            if vertex.distanceSquared(toSegment: a, b) <= radiusSquared {
                return true
            }
        }
        return false
    }

    private func segmentDistanceSquared(_ a1: CGPoint, _ a2: CGPoint, _ b1: CGPoint, _ b2: CGPoint) -> CGFloat {
        if segmentsIntersect(a1, a2, b1, b2) { return 0 }
        return min(
            a1.distanceSquared(toSegment: b1, b2),
            a2.distanceSquared(toSegment: b1, b2),
            b1.distanceSquared(toSegment: a1, a2),
            b2.distanceSquared(toSegment: a1, a2)
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
}
