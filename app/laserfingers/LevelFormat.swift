import Foundation
import CoreGraphics

struct Level: Identifiable, Codable, Hashable {
    struct Coordinate: Codable, Hashable {
        let x: CGFloat
        let y: CGFloat
    }
    
    enum ButtonShape: String, Codable, Hashable {
        case circle
        case square
        case capsule
    }
    
    struct ButtonPad: Identifiable, Codable, Hashable {
        let id: String
        let shape: ButtonShape
        let position: Coordinate
        /// Normalized size relative to the shortest scene edge (0-1)
        let size: CGFloat
    }
    
    struct ButtonSet: Identifiable, Codable, Hashable {
        enum Mode: String, Codable {
            case any
            case all
        }
        
        enum Kind: String, Codable {
            case charge
            case `switch`
        }
        
        let id: String
        let mode: Mode
        let kind: Kind?
        /// When true, the buttons in this set drain unless actively pressed
        let isDrainer: Bool?
        /// Seconds needed to make full progress while the set condition is satisfied
        let timeToFull: Double
        let fillColor: String
        let glowColor: String?
        let rimColor: String?
        let pads: [ButtonPad]
        /// Laser controlled by this set, if any
        let controls: String?
        /// Whether this set must be completed to win
        let required: Bool?
    }
    
    struct Button: Identifiable, Codable, Hashable {
        let id: String
        let shape: ButtonShape
        let position: Coordinate
        let size: CGFloat
        let fillColor: String
        let glowColor: String?
        let rimColor: String?
        let timeToFull: Double
        let isDrainer: Bool?
    }
    
    struct ButtonCluster: Identifiable, Codable, Hashable {
        enum Mode: String, Codable {
            case any
            case all
        }
        
        let id: String
        let mode: Mode
        let buttons: [String]
        /// Seconds needed for this cluster to charge fully when active
        let timeToFull: Double
    }
    
    struct Laser: Identifiable, Codable, Hashable {
        enum LaserType: String, Codable {
            case sweep
            case rotate
            case segment
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
        /// Seconds for a full sweep/rotation cycle (sweep/rotate only)
        let speed: Double?
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
        /// Segment-only: first endpoint
        let startPoint: Coordinate?
        /// Segment-only: second endpoint
        let endPoint: Coordinate?
        /// Segment-only: seconds between on/off toggles
        let togglePeriod: Double?
    }
    
    let id: String
    let title: String
    let description: String
    let allowedTouches: Int
    let difficulty: Int
    let buttons: [Button]
    let buttonClusters: [ButtonCluster]?
    let buttonSets: [ButtonSet]?
    let lasers: [Laser]
    let unlocks: [Int]?
}

extension Level {
    var resolvedButtonSets: [ButtonSet] {
        if let sets = buttonSets, !sets.isEmpty {
            return sets
        }
        if let clusters = buttonClusters, !clusters.isEmpty {
            return clusters.compactMap { cluster in
                let members = buttons.filter { cluster.buttons.contains($0.id) }
                guard let first = members.first else { return nil }
                let pads = members.map {
                    ButtonPad(id: $0.id, shape: $0.shape, position: $0.position, size: $0.size)
                }
                return ButtonSet(
                    id: cluster.id,
                    mode: ButtonSet.Mode(rawValue: cluster.mode.rawValue) ?? .any,
                    kind: .charge,
                    isDrainer: members.first?.isDrainer,
                    timeToFull: cluster.timeToFull,
                    fillColor: first.fillColor,
                    glowColor: first.glowColor,
                    rimColor: first.rimColor,
                    pads: pads,
                    controls: nil,
                    required: true
                )
            }
        }
        let derived = buttons.map {
            ButtonSet(
                id: "auto-\($0.id)",
                mode: .any,
                kind: .charge,
                isDrainer: $0.isDrainer,
                timeToFull: $0.timeToFull,
                fillColor: $0.fillColor,
                glowColor: $0.glowColor,
                rimColor: $0.rimColor,
                pads: [
                    ButtonPad(id: $0.id, shape: $0.shape, position: $0.position, size: $0.size)
                ],
                controls: nil,
                required: true
            )
        }
        return derived
    }
}
