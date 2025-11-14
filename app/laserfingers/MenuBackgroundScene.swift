import SpriteKit

final class MenuBackgroundScene: SKScene {
    private let baseNode = SKSpriteNode(color: SKColor(red: 0.04, green: 0.01, blue: 0.08, alpha: 1), size: .zero)
    private let glowNode = SKShapeNode(circleOfRadius: 240)
    private let gridNode = SKShapeNode()
    private var laserNodes: [SKShapeNode] = []

    override init() {
        super.init(size: CGSize(width: 1920, height: 1080))
        scaleMode = .resizeFill
        backgroundColor = .clear
        setupNodes()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
        layoutNodes()
        startAnimations()
    }
    
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutNodes()
    }
    
    private func setupNodes() {
        baseNode.alpha = 0.95
        addChild(baseNode)
        
        glowNode.fillColor = SKColor(red: 0.95, green: 0.3, blue: 1, alpha: 0.35)
        glowNode.strokeColor = .clear
        glowNode.glowWidth = 80
        glowNode.zPosition = -5
        addChild(glowNode)
        
        gridNode.strokeColor = SKColor.white.withAlphaComponent(0.06)
        gridNode.lineWidth = 1
        gridNode.zPosition = -4
        addChild(gridNode)
    }
    
    private func layoutNodes() {
        baseNode.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)
        baseNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        
        glowNode.path = CGPath(ellipseIn: CGRect(x: -size.width * 0.35, y: -size.width * 0.35, width: size.width * 0.7, height: size.width * 0.7), transform: nil)
        glowNode.position = CGPoint(x: size.width * 0.25, y: size.height * 0.35)
        
        gridNode.path = makeGridPath(size: size)
    }
    
    private func startAnimations() {
        let rotate = SKAction.rotate(byAngle: .pi * 2, duration: 80)
        baseNode.run(SKAction.repeatForever(rotate))
        
        let pulseUp = SKAction.group([
            SKAction.scale(to: 1.08, duration: 6),
            SKAction.fadeAlpha(to: 0.45, duration: 6)
        ])
        let pulseDown = SKAction.group([
            SKAction.scale(to: 0.92, duration: 6),
            SKAction.fadeAlpha(to: 0.25, duration: 6)
        ])
        glowNode.run(SKAction.repeatForever(SKAction.sequence([pulseUp, pulseDown])))
        
        let drift = SKAction.sequence([
            SKAction.moveBy(x: 20, y: -15, duration: 10),
            SKAction.moveBy(x: -20, y: 15, duration: 10)
        ])
        gridNode.run(SKAction.repeatForever(drift))
    }
    
    private func makeGridPath(size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let spacing: CGFloat = 80
        var x: CGFloat = 0
        while x <= size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        return path
    }
}
