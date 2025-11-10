import Foundation
import CoreGraphics

struct Level: Identifiable, Codable, Hashable {
    struct Coordinate: Codable, Hashable {
        let x: CGFloat
        let y: CGFloat
    }
    
    struct Button: Identifiable, Codable, Hashable {
        enum Shape: String, Codable {
            case circle
            case square
            case capsule
        }
        
        let id: String
        let shape: Shape
        let position: Coordinate
        /// Normalized size relative to the shortest scene edge (0-1)
        let size: CGFloat
        let fillColor: String
        let glowColor: String?
        let rimColor: String?
        /// Seconds needed to make full progress while pressing this button
        let timeToFull: Double
    }
    
    struct Laser: Identifiable, Codable, Hashable {
        enum LaserType: String, Codable {
            case sweep
            case rotate
        }
        
        enum Axis: String, Codable {
            case horizontal
            case vertical
            case diagonal
        }
        
        enum Rotation: String, Codable {
            case clockwise
            case counterclockwise
        }
        
        let id: String
        let type: LaserType
        let color: String
        /// Seconds for a full sweep/rotation cycle
        let speed: Double
        /// Normalized beam thickness relative to the shortest scene edge
        let thickness: CGFloat
        /// Normalized magnitude for sweep travel
        let travel: CGFloat?
        /// Position offset for sweep lasers (0-1 across perpendicular axis)
        let offset: CGFloat?
        let axis: Axis?
        /// Normalized center coordinate for rotating lasers
        let center: Coordinate?
        /// Normalized radius for rotating lasers
        let radius: CGFloat?
        let direction: Rotation?
        /// Optional phase offset in seconds for staggering lasers
        let phase: Double?
    }
    
    let id: Int
    let title: String
    let description: String
    let allowedTouches: Int
    let difficulty: Int
    let buttons: [Button]
    let lasers: [Laser]
}

extension Level {
    var averageChargeDuration: Double {
        guard !buttons.isEmpty else { return 3 }
        let total = buttons.reduce(0.0) { $0 + max($1.timeToFull, 0.1) }
        return total / Double(buttons.count)
    }
}

struct LevelManifest: Codable {
    let levels: [Level]
}

extension Level {
    static var fallback: [Level] {
        return [
            Level(
                id: 1,
                title: "Warmup Beam",
                description: "Single core button with opposing sweeps.",
                allowedTouches: 2,
                difficulty: 1,
                buttons: [
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
                ],
                lasers: [
                    Level.Laser(
                        id: "sweep-horizontal",
                        type: .sweep,
                        color: "#28E0FF",
                        speed: 3.5,
                        thickness: 0.02,
                        travel: 0.3,
                        offset: 0.5,
                        axis: .horizontal,
                        center: nil,
                        radius: nil,
                        direction: nil,
                        phase: 0
                    )
                ]
            )
        ]
    }
}
