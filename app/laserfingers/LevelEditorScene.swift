import SpriteKit

protocol LevelEditorSceneDelegate: AnyObject {
    func editorScene(_ scene: LevelEditorScene, didTapNormalized point: Level.NormalizedPoint)
    func editorScene(_ scene: LevelEditorScene, didSelectButtonID buttonID: String, hitAreaID: String?)
    func editorScene(_ scene: LevelEditorScene, didSelectLaserID laserID: String)
}

final class LevelEditorScene: LevelSceneBase {
    weak var editorDelegate: LevelEditorSceneDelegate?
    
    override func didMove(to view: SKView) {
        super.didMove(to: view)
    }
    
    override func setPlaybackState(_ state: PlaybackState) {
        super.setPlaybackState(state)
        isPaused = state == .paused
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        if playbackState == .paused {
            if let button = buttonSelection(at: location) {
                editorDelegate?.editorScene(self, didSelectButtonID: button.0.id, hitAreaID: button.1?.id)
                return
            }
            
            if let laser = laserSelection(at: location) {
                editorDelegate?.editorScene(self, didSelectLaserID: laser.id)
                return
            }
        }
        
        guard let normalized = normalizedPoint(from: location) else { return }
        editorDelegate?.editorScene(self, didTapNormalized: normalized)
    }
}
