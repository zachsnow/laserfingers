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
    private let cameraNode = SKCameraNode()

    var zoomScale: CGFloat = 1.0 {
        didSet {
            updateCamera()
        }
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        setupCamera()
    }

    private func setupCamera() {
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
        updateCamera()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func updateCamera() {
        cameraNode.setScale(1.0 / zoomScale)
    }

    private func convertTouchLocation(_ touch: UITouch) -> CGPoint {
        // Get the touch location in the view
        guard let view = self.view else {
            return touch.location(in: self)
        }
        let locationInView = touch.location(in: view)

        // Convert from view coordinates to scene coordinates
        // When we have a camera, we need to account for the camera's transform
        let locationInScene = convertPoint(fromView: locationInView)

        return locationInScene
    }

    override func normalizedPoint(from scenePoint: CGPoint) -> Level.NormalizedPoint? {
        // When zoomed, we need to account for the camera's scale
        // The scene point is already in camera-transformed coordinates
        // We need to normalize based on the actual visible area, not the frame
        guard let transform = layoutTransform else { return nil }
        let result = transform.normalizedPoint(from: scenePoint, zoomScale: zoomScale)
        print("🔍 normalizedPoint: scenePoint=\(scenePoint), zoomScale=\(zoomScale), result=\(String(describing: result))")
        return result
    }

    override func setPlaybackState(_ state: PlaybackState) {
        super.setPlaybackState(state)
        isPaused = state == .paused
        showPathPointHandles = state == .paused
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard playbackState == .paused else { return }
        guard let touch = touches.first else { return }
        let location = convertTouchLocation(touch)

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
        let location = convertTouchLocation(touch)

        // Update handle position during drag
        if let handle = draggingHandle {
            handle.position = location
            // Update connected lines in real-time
            updateLinesForHandle(handle)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = convertTouchLocation(touch)

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

    private func updateLinesForHandle(_ handle: PathPointHandleNode) {
        guard let laserID = handle.laserID, let pointIndex = handle.pointIndex else { return }

        // Find which lines connect to this handle
        // We need to update lines that connect this point to adjacent points
        guard let laser = level.lasers.first(where: { $0.id == laserID }) else { return }

        // Calculate which lines need updating based on the laser type and point index
        var lineIndicesToUpdate: [Int] = []
        var lineIndex = 0

        for currentLaser in level.lasers {
            if let rayLaser = currentLaser as? Level.RayLaser {
                let pointCount = rayLaser.endpoint.points.count
                if currentLaser.id == laserID && pointCount > 1 {
                    // This is the laser being dragged
                    // Update line before this point (if exists)
                    if pointIndex > 0 {
                        lineIndicesToUpdate.append(lineIndex + pointIndex - 1)
                    }
                    // Update line after this point (if exists)
                    if pointIndex < pointCount - 1 {
                        lineIndicesToUpdate.append(lineIndex + pointIndex)
                    }
                }
                // Advance line index for this laser's lines
                if pointCount > 1 {
                    lineIndex += pointCount - 1
                }
            } else if let segmentLaser = currentLaser as? Level.SegmentLaser {
                let startCount = segmentLaser.startEndpoint.points.count
                let endCount = segmentLaser.endEndpoint.points.count

                if currentLaser.id == laserID {
                    if pointIndex >= 0 && startCount > 1 {
                        // Start endpoint
                        if pointIndex > 0 {
                            lineIndicesToUpdate.append(lineIndex + pointIndex - 1)
                        }
                        if pointIndex < startCount - 1 {
                            lineIndicesToUpdate.append(lineIndex + pointIndex)
                        }
                    } else if pointIndex < 0 && endCount > 1 {
                        // End endpoint (negative index)
                        let actualIndex = -(pointIndex + 1)
                        let endLineStartIndex = lineIndex + (startCount > 1 ? startCount - 1 : 0)
                        if actualIndex > 0 {
                            lineIndicesToUpdate.append(endLineStartIndex + actualIndex - 1)
                        }
                        if actualIndex < endCount - 1 {
                            lineIndicesToUpdate.append(endLineStartIndex + actualIndex)
                        }
                    }
                }

                // Advance line index for this laser's lines
                if startCount > 1 {
                    lineIndex += startCount - 1
                }
                if endCount > 1 {
                    lineIndex += endCount - 1
                }
            }
        }

        // Update the identified lines with the handle's current position
        for index in lineIndicesToUpdate {
            if index < pathPointLines.count {
                updateLineAtIndex(index, forHandle: handle)
            }
        }
    }

    private func updateLineAtIndex(_ index: Int, forHandle handle: PathPointHandleNode) {
        guard let laserID = handle.laserID, let pointIndex = handle.pointIndex else { return }
        guard let laser = level.lasers.first(where: { $0.id == laserID }) else { return }
        guard let transform = layoutTransform else { return }

        let line = pathPointLines[index]

        // Determine which endpoints the line connects
        if let rayLaser = laser as? Level.RayLaser {
            let points = rayLaser.endpoint.points
            guard pointIndex >= 0 && pointIndex < points.count else { return }

            // Determine if this line connects to the previous or next point
            let lineConnectsToPrevious = pointIndex > 0
            let lineConnectsToNext = pointIndex < points.count - 1

            if lineConnectsToPrevious && index == getLineIndexBefore(laserID, pointIndex: pointIndex) {
                // Line from previous point to this point
                let start = transform.point(from: points[pointIndex - 1])
                let end = handle.position
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)
                line.path = path
            } else if lineConnectsToNext {
                // Line from this point to next point
                let start = handle.position
                let end = transform.point(from: points[pointIndex + 1])
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)
                line.path = path
            }
        }
        // Similar logic would be needed for segment lasers, but keeping it simple for now
    }

    private func getLineIndexBefore(_ laserID: String, pointIndex: Int) -> Int {
        // Calculate the line index for the line before this point
        var lineIndex = 0
        for laser in level.lasers {
            if laser.id == laserID {
                return lineIndex + pointIndex - 1
            }
            if let rayLaser = laser as? Level.RayLaser {
                if rayLaser.endpoint.points.count > 1 {
                    lineIndex += rayLaser.endpoint.points.count - 1
                }
            } else if let segmentLaser = laser as? Level.SegmentLaser {
                if segmentLaser.startEndpoint.points.count > 1 {
                    lineIndex += segmentLaser.startEndpoint.points.count - 1
                }
                if segmentLaser.endEndpoint.points.count > 1 {
                    lineIndex += segmentLaser.endEndpoint.points.count - 1
                }
            }
        }
        return lineIndex
    }
}
