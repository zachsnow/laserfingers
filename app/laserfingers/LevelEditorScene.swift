import SpriteKit

protocol LevelEditorSceneDelegate: AnyObject {
    func editorScene(_ scene: LevelEditorScene, didTapNormalized point: Level.NormalizedPoint)
    func editorScene(_ scene: LevelEditorScene, didSelectButtonID buttonID: String, hitAreaID: String?)
    func editorScene(_ scene: LevelEditorScene, didSelectLaserID laserID: String)
    func editorScene(_ scene: LevelEditorScene, didDragPathPoint laserID: String, pointIndex: Int, to point: Level.NormalizedPoint)
    func editorScene(_ scene: LevelEditorScene, didDragButton buttonID: String, to point: Level.NormalizedPoint)
}

final class LevelEditorScene: LevelSceneBase {
    weak var editorDelegate: LevelEditorSceneDelegate?

    private var draggingHandle: PathPointHandleNode?
    private var dragStartPosition: CGPoint?

    override func didMove(to view: SKView) {
        super.didMove(to: view)
    }

    override func setPlaybackState(_ state: PlaybackState) {
        super.setPlaybackState(state)
        isPaused = state == .paused
        showPathPointHandles = state == .paused
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard playbackState == .paused else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Check if we're touching a path point handle
        if let handle = pathPointHandleSelection(at: location) {
            draggingHandle = handle
            dragStartPosition = location
            handle.setHighlighted(true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard playbackState == .paused else { return }
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Update handle position during drag
        if let handle = draggingHandle {
            handle.position = location
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Handle drag completion or tap
        if let handle = draggingHandle, playbackState == .paused {
            handle.setHighlighted(false)

            // Check if this was a tap (minimal movement) or a drag
            let dragDistance: CGFloat
            if let dragStart = dragStartPosition {
                let dx = location.x - dragStart.x
                let dy = location.y - dragStart.y
                dragDistance = sqrt(dx * dx + dy * dy)
            } else {
                dragDistance = 0
            }

            // If movement was minimal, treat as a tap to show settings
            if dragDistance < 10 {
                // Notify delegate of handle tap to show settings
                if let laserID = handle.laserID {
                    editorDelegate?.editorScene(self, didSelectLaserID: laserID)
                } else if let buttonID = handle.buttonID {
                    editorDelegate?.editorScene(self, didSelectButtonID: buttonID, hitAreaID: nil)
                }
                draggingHandle = nil
                dragStartPosition = nil
                return
            }

            // Otherwise, it's a drag - update the position
            guard let normalized = normalizedPoint(from: location) else {
                // Reset handle if we couldn't normalize the point
                if let dragStart = dragStartPosition {
                    handle.position = dragStart
                }
                draggingHandle = nil
                dragStartPosition = nil
                return
            }

            // Notify delegate of the drag
            if let laserID = handle.laserID, let pointIndex = handle.pointIndex {
                editorDelegate?.editorScene(self, didDragPathPoint: laserID, pointIndex: pointIndex, to: normalized)
            } else if let buttonID = handle.buttonID {
                editorDelegate?.editorScene(self, didDragButton: buttonID, to: normalized)
            }

            draggingHandle = nil
            dragStartPosition = nil
            return
        }

        // Handle selection (only if we didn't drag)
        if playbackState == .paused && draggingHandle == nil {
            if let button = buttonSelection(at: location) {
                editorDelegate?.editorScene(self, didSelectButtonID: button.0.id, hitAreaID: button.1?.id)
                return
            }

            if let laser = laserSelection(at: location) {
                editorDelegate?.editorScene(self, didSelectLaserID: laser.id)
                return
            }
        }

        // Handle tap for adding new objects
        guard let normalized = normalizedPoint(from: location) else { return }
        editorDelegate?.editorScene(self, didTapNormalized: normalized)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Reset drag state if touch is cancelled
        if let handle = draggingHandle {
            handle.setHighlighted(false)
            if let dragStart = dragStartPosition {
                handle.position = dragStart
            }
        }
        draggingHandle = nil
        dragStartPosition = nil
    }
}
