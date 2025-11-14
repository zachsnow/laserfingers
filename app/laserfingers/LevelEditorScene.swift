import SpriteKit

enum PathPointOwner {
    case rayLaser(id: String)
    case segmentLaserStart(id: String)
    case segmentLaserEnd(id: String)
    case button(id: String)
}

protocol LevelEditorSceneDelegate: AnyObject {
    func editorScene(_ scene: LevelEditorScene, didTapNormalized point: Level.NormalizedPoint)
    func editorScene(_ scene: LevelEditorScene, didSelectButtonID buttonID: String, hitAreaID: String?)
    func editorScene(_ scene: LevelEditorScene, didSelectLaserID laserID: String)
    func editorScene(_ scene: LevelEditorScene, didDragPathPoint owner: PathPointOwner, pointIndex: Int, to point: Level.NormalizedPoint)
    func editorScene(_ scene: LevelEditorScene, snapPoint point: Level.NormalizedPoint) -> Level.NormalizedPoint
}

final class LevelEditorScene: LevelSceneBase {
    weak var editorDelegate: LevelEditorSceneDelegate?

    private var draggingHandle: PathPointHandleNode?
    private var dragStartPosition: CGPoint?
    private let cameraNode = SKCameraNode()
    private var gridLayer: SKNode?

    var zoomScale: CGFloat = 1.0 {
        didSet {
            AppLog.zoom.debug("Zoom changed from \(oldValue) to \(zoomScale)")
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
        AppLog.scene.notice("Camera setup at position (\(cameraNode.position.x), \(cameraNode.position.y)) with size (\(size.width), \(size.height))")
        updateCamera()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        AppLog.scene.notice("Scene size changed from (\(oldSize.width), \(oldSize.height)) to (\(size.width), \(size.height))")
        // Redraw grid with updated layout transform
        if let delegate = editorDelegate as? LevelEditorViewModel {
            updateGrid(interval: delegate.snapInterval, enabled: delegate.isGridEnabled)
        }
    }

    private func updateCamera() {
        cameraNode.setScale(1.0 / zoomScale)
    }

    private func convertTouchLocation(_ touch: UITouch) -> CGPoint {
        // Get the touch location in the view
        guard let view = self.view else {
            AppLog.touch.warning("convertTouchLocation called with nil view")
            return touch.location(in: self)
        }
        let locationInView = touch.location(in: view)

        // Convert from view coordinates to scene coordinates
        // When we have a camera, we need to account for the camera's transform
        let locationInScene = convertPoint(fromView: locationInView)

        AppLog.touch.debug("viewLocation=(\(locationInView.x), \(locationInView.y)) -> sceneLocation=(\(locationInScene.x), \(locationInScene.y))")
        return locationInScene
    }

    override func normalizedPoint(from scenePoint: CGPoint) -> Level.NormalizedPoint? {
        // When zoomed, we need to account for the camera's scale
        // The scene point is already in camera-transformed coordinates
        // We need to normalize based on the actual visible area, not the frame
        guard let transform = layoutTransform else {
            AppLog.coordinates.warning("normalizedPoint called with nil layoutTransform")
            return nil
        }
        let result = transform.normalizedPoint(from: scenePoint, zoomScale: zoomScale)
        AppLog.coordinates.debug("scenePoint=(\(scenePoint.x), \(scenePoint.y)) zoomScale=\(zoomScale) -> normalized=(\(result?.x ?? 0), \(result?.y ?? 0))")
        return result
    }

    override func setPlaybackState(_ state: PlaybackState) {
        super.setPlaybackState(state)
        isPaused = state == .paused
        showPathPointHandles = state == .paused
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard playbackState == .paused else {
            AppLog.touch.debug("touchesBegan ignored - not paused")
            return
        }
        guard let touch = touches.first else { return }
        let location = convertTouchLocation(touch)

        // Check if we're touching a path point handle
        if let handle = pathPointHandleSelection(at: location) {
            AppLog.touch.notice("Touch began on handle: ownerType=\(handle.ownerType) ownerID=\(handle.ownerID) endpointIndex=\(handle.endpointIndex) pointIndex=\(handle.pointIndex)")
            draggingHandle = handle
            dragStartPosition = location
            handle.setHighlighted(true)
        } else {
            AppLog.touch.debug("Touch began at (\(location.x), \(location.y)) - no handle selected")
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard playbackState == .paused else { return }
        guard let touch = touches.first else { return }
        let location = convertTouchLocation(touch)

        // Update handle position during drag
        if let handle = draggingHandle {
            // Apply snapping during drag for visual feedback
            if let transform = layoutTransform, let normalized = transform.normalizedPoint(from: location, zoomScale: zoomScale) {
                let snapped = editorDelegate?.editorScene(self, snapPoint: normalized) ?? normalized
                let snappedScreen = transform.point(from: snapped)
                handle.position = snappedScreen
            } else {
                handle.position = location
            }
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
                AppLog.touch.notice("Handle tapped (drag distance \(dragDistance))")
                // Notify delegate of handle tap to show settings
                if handle.ownerType == "laser" {
                    editorDelegate?.editorScene(self, didSelectLaserID: handle.ownerID)
                } else if handle.ownerType == "button" {
                    editorDelegate?.editorScene(self, didSelectButtonID: handle.ownerID, hitAreaID: nil)
                }
                draggingHandle = nil
                dragStartPosition = nil
                return
            }

            // Otherwise, it's a drag - update the position
            guard let normalized = normalizedPoint(from: location) else {
                AppLog.coordinates.warning("Failed to normalize point after drag")
                // Reset handle if we couldn't normalize the point
                if let dragStart = dragStartPosition {
                    handle.position = dragStart
                }
                draggingHandle = nil
                dragStartPosition = nil
                return
            }

            AppLog.touch.notice("Handle dragged distance=\(dragDistance) to normalized=(\(normalized.x), \(normalized.y))")
            // Notify delegate of the drag
            if let owner = pathPointOwner(for: handle) {
                editorDelegate?.editorScene(self, didDragPathPoint: owner, pointIndex: handle.pointIndex, to: normalized)
            }

            draggingHandle = nil
            dragStartPosition = nil
            return
        }

        // Handle selection (only if we didn't drag)
        if playbackState == .paused && draggingHandle == nil {
            if let button = buttonSelection(at: location) {
                AppLog.touch.notice("Button selected: \(button.0.id)")
                editorDelegate?.editorScene(self, didSelectButtonID: button.0.id, hitAreaID: button.1?.id)
                return
            }

            if let laser = laserSelection(at: location) {
                AppLog.touch.notice("Laser selected: \(laser.id)")
                editorDelegate?.editorScene(self, didSelectLaserID: laser.id)
                return
            }
        }

        // Handle tap for adding new objects
        guard let normalized = normalizedPoint(from: location) else {
            AppLog.coordinates.warning("Failed to normalize tap location")
            return
        }
        AppLog.touch.notice("Tap for new object at normalized=(\(normalized.x), \(normalized.y))")
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
        if handle.ownerType == "button" {
            updateLinesForButtonHandle(handle, buttonID: handle.ownerID, pointIndex: handle.pointIndex)
        } else if handle.ownerType == "laser" {
            updateLinesForLaserHandle(handle, laserID: handle.ownerID, pointIndex: handle.pointIndex)
        }
    }

    private func updateLinesForLaserHandle(_ handle: PathPointHandleNode, laserID: String, pointIndex: Int) {
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

    private func updateLinesForButtonHandle(_ handle: PathPointHandleNode, buttonID: String, pointIndex: Int) {
        guard let button = level.buttons.first(where: { $0.id == buttonID }) else { return }
        guard let transform = layoutTransform else { return }

        let pointCount = button.endpoint.points.count
        guard pointCount > 1 else { return }

        // Calculate the line index offset (all laser lines come first)
        var lineIndex = 0
        for laser in level.lasers {
            if let rayLaser = laser as? Level.RayLaser, rayLaser.endpoint.points.count > 1 {
                lineIndex += rayLaser.endpoint.points.count - 1
            } else if let segmentLaser = laser as? Level.SegmentLaser {
                if segmentLaser.startEndpoint.points.count > 1 {
                    lineIndex += segmentLaser.startEndpoint.points.count - 1
                }
                if segmentLaser.endEndpoint.points.count > 1 {
                    lineIndex += segmentLaser.endEndpoint.points.count - 1
                }
            }
        }

        // Add offset for buttons before this one
        for otherButton in level.buttons {
            if otherButton.id == buttonID {
                break
            }
            if otherButton.endpoint.points.count > 1 {
                lineIndex += otherButton.endpoint.points.count - 1
            }
        }

        // Update lines connected to this point
        let points = button.endpoint.points
        var lineIndicesToUpdate: [Int] = []

        // Line before this point (if exists)
        if pointIndex > 0 {
            lineIndicesToUpdate.append(lineIndex + pointIndex - 1)
        }
        // Line after this point (if exists)
        if pointIndex < pointCount - 1 {
            lineIndicesToUpdate.append(lineIndex + pointIndex)
        }

        // Update the lines
        for index in lineIndicesToUpdate {
            guard index < pathPointLines.count else { continue }
            let line = pathPointLines[index]

            // Determine which points this line connects
            if pointIndex > 0 && index == lineIndex + pointIndex - 1 {
                // Line from previous point to this point
                let start = transform.point(from: points[pointIndex - 1])
                let end = handle.position
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)
                line.path = path
            } else if pointIndex < pointCount - 1 && index == lineIndex + pointIndex {
                // Line from this point to next point
                let start = handle.position
                let end = transform.point(from: points[pointIndex + 1])
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: end)
                line.path = path
            }
        }
    }

    private func updateLineAtIndex(_ index: Int, forHandle handle: PathPointHandleNode) {
        guard handle.ownerType == "laser" else { return }
        guard let laser = level.lasers.first(where: { $0.id == handle.ownerID }) else { return }
        guard let transform = layoutTransform else { return }
        let laserID = handle.ownerID
        let pointIndex = handle.pointIndex

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

    private func pathPointOwner(for handle: PathPointHandleNode) -> PathPointOwner? {
        if handle.ownerType == "button" {
            return .button(id: handle.ownerID)
        } else if handle.ownerType == "laser" {
            guard let laser = level.lasers.first(where: { $0.id == handle.ownerID }) else { return nil }

            if laser is Level.RayLaser {
                return .rayLaser(id: handle.ownerID)
            } else if laser is Level.SegmentLaser {
                // endpointIndex 0 = start, 1 = end
                return handle.endpointIndex == 1 ? .segmentLaserEnd(id: handle.ownerID) : .segmentLaserStart(id: handle.ownerID)
            }
        }
        return nil
    }

    func updateGrid(interval: CGFloat?, enabled: Bool) {
        AppLog.editor.notice("updateGrid called: interval=\(interval?.description ?? "nil") enabled=\(enabled) layoutTransform=\(layoutTransform != nil)")
        gridLayer?.removeFromParent()
        gridLayer = nil

        guard enabled, let interval = interval, let transform = layoutTransform else {
            AppLog.editor.notice("updateGrid early return: enabled=\(enabled) interval=\(interval?.description ?? "nil") transform=\(layoutTransform != nil)")
            return
        }

        let grid = SKNode()
        grid.zPosition = -100

        let gridColor = SKColor(white: 0.8, alpha: 0.3)

        // Calculate grid range based on normalized coordinates
        let minCoord: CGFloat = -2.0
        let maxCoord: CGFloat = 2.0

        // Vertical lines
        var x = (minCoord / interval).rounded() * interval
        var lineCount = 0
        while x <= maxCoord {
            let topPoint = transform.point(from: Level.NormalizedPoint(x: x, y: maxCoord))
            let bottomPoint = transform.point(from: Level.NormalizedPoint(x: x, y: minCoord))
            if lineCount == 0 {
                AppLog.editor.notice("First vertical line: x=\(x) from (\(bottomPoint.x), \(bottomPoint.y)) to (\(topPoint.x), \(topPoint.y))")
            }
            lineCount += 1

            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: bottomPoint)
            path.addLine(to: topPoint)
            line.path = path
            line.strokeColor = gridColor
            line.lineWidth = 1
            line.isAntialiased = true
            line.lineCap = .round
            grid.addChild(line)

            x += interval
        }

        // Horizontal lines
        var y = (minCoord / interval).rounded() * interval
        while y <= maxCoord {
            let leftPoint = transform.point(from: Level.NormalizedPoint(x: minCoord, y: y))
            let rightPoint = transform.point(from: Level.NormalizedPoint(x: maxCoord, y: y))

            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: leftPoint)
            path.addLine(to: rightPoint)
            line.path = path
            line.strokeColor = gridColor
            line.lineWidth = 1
            line.isAntialiased = true
            line.lineCap = .round
            grid.addChild(line)

            y += interval
        }

        addChild(grid)
        gridLayer = grid
        AppLog.editor.notice("Grid added with \(grid.children.count) lines at z=\(grid.zPosition)")
    }
}
