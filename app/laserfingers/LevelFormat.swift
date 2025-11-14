import Foundation
import CoreGraphics

struct Level: Identifiable, Codable, Hashable {
    struct NormalizedPoint: Codable, Hashable {
        let x: CGFloat
        let y: CGFloat
    }
    
    enum Device: String, Codable, Hashable {
        case iPhone = "iPhone"
        case iPadMini = "iPad Mini"
        case iPad = "iPad"
    }
    
    struct Button: Identifiable, Codable, Hashable {
        struct Timing: Codable, Hashable {
            /// Seconds to reach a full charge while conditions are met. Zero means instantaneous.
            let chargeSeconds: Double
            /// Seconds to hold a full charge after touches stop. Nil = indefinite, zero = drain immediately.
            let holdSeconds: Double?
            /// Seconds to drain completely once hold time has expired. Zero means instantaneous.
            let drainSeconds: Double
        }
        
        struct ColorSpec: Codable, Hashable {
            let fill: String
            let glow: String?
            let rim: String?
        }
        
        enum HitLogic: String, Codable {
            case any
            case all
        }
        
        struct HitArea: Identifiable, Codable, Hashable {
            enum Shape: Hashable {
                case circle(radius: CGFloat)
                case rectangle(width: CGFloat, height: CGFloat, cornerRadius: CGFloat?)
                case capsule(length: CGFloat, radius: CGFloat)
                case polygon(points: [NormalizedPoint])
            }
            
            let id: String
            let shape: Shape
            /// Position relative to the owning button's position.
            let offset: NormalizedPoint
            /// Rotation in degrees applied after positioning. Defaults to 0.
            let rotationDegrees: CGFloat?
        }
        
        struct Effect: Codable, Hashable {
            enum Trigger: String, Codable {
                case touchStarted
                case touchEnded
                case turnedOn
                case turnedOff
            }
            
            struct Action: Codable, Hashable {
                enum Kind: String, Codable {
                    case turnOnLasers
                    case turnOffLasers
                    case toggleLasers
                }
                
                let kind: Kind
                /// Laser identifiers the action targets.
                let lasers: [String]
            }
            
            let trigger: Trigger
            let action: Action
        }
        
        let id: String
        /// Anchor used for positioning hit areas.
        let position: NormalizedPoint
        let timing: Timing
        let hitLogic: HitLogic
        let required: Bool
        let color: ColorSpec
        let hitAreas: [HitArea]
        let effects: [Effect]
    }
    
    // MARK: - Laser Types

    struct CadenceStep: Codable, Hashable {
        enum State: String, Codable {
            case on
            case off
        }

        let state: State
        /// Duration to stay in the given state. Nil = hold indefinitely.
        let duration: Double?
    }

    struct EndpointPath: Codable, Hashable {
        let points: [NormalizedPoint]
        /// Seconds for a full round-trip cycle (point[0] -> point[1] -> point[0]).
        /// Nil for stationary (single point), required for moving (2 points).
        let cycleSeconds: Double?
        /// Starting position along path, 0-1. Defaults to 0.
        let t: Double

        private enum CodingKeys: String, CodingKey {
            case points
            case cycleSeconds
            case t
        }

        init(points: [NormalizedPoint], cycleSeconds: Double? = nil, t: Double = 0) {
            self.points = points
            self.cycleSeconds = cycleSeconds
            self.t = t
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            points = try container.decode([NormalizedPoint].self, forKey: .points)
            cycleSeconds = try container.decodeIfPresent(Double.self, forKey: .cycleSeconds)
            t = try container.decodeIfPresent(Double.self, forKey: .t) ?? 0.0
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(points, forKey: .points)
            try container.encodeIfPresent(cycleSeconds, forKey: .cycleSeconds)
            if t != 0.0 {
                try container.encode(t, forKey: .t)
            }
        }

        var isStationary: Bool {
            return points.count == 1
        }
    }

    class Laser: Identifiable, Codable, Hashable {
        let id: String
        let color: String
        /// Normalized beam thickness relative to the shortest scene edge.
        let thickness: CGFloat
        /// Cadence applied to the firing state. Nil or empty => always on.
        let cadence: [CadenceStep]?
        var enabled: Bool

        /// Dynamically dispatched equality check - subclasses override to include their specific properties
        func isEqual(to other: Laser) -> Bool {
            return id == other.id &&
                   color == other.color &&
                   thickness == other.thickness &&
                   cadence == other.cadence &&
                   enabled == other.enabled
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case id
            case color
            case thickness
            case cadence
            case enabled
        }

        private enum LaserType: String, Codable {
            case ray
            case segment
        }

        init(id: String, color: String, thickness: CGFloat, cadence: [CadenceStep]?, enabled: Bool = true) {
            self.id = id
            self.color = color
            self.thickness = thickness
            self.cadence = cadence
            self.enabled = enabled
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            color = try container.decode(String.self, forKey: .color)
            thickness = try container.decode(CGFloat.self, forKey: .thickness)
            cadence = try container.decodeIfPresent([CadenceStep].self, forKey: .cadence)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(color, forKey: .color)
            try container.encode(thickness, forKey: .thickness)
            try container.encodeIfPresent(cadence, forKey: .cadence)
            try container.encode(enabled, forKey: .enabled)
        }

        static func == (lhs: Laser, rhs: Laser) -> Bool {
            return lhs.isEqual(to: rhs)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
            hasher.combine(color)
            hasher.combine(thickness)
            hasher.combine(cadence)
            hasher.combine(enabled)
        }

        // Factory method for decoding the correct subclass
        static func decode(from decoder: Decoder) throws -> Laser {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(LaserType.self, forKey: .type)

            switch type {
            case .ray:
                return try RayLaser(from: decoder)
            case .segment:
                return try SegmentLaser(from: decoder)
            }
        }

        // Encode with type discrimination
        func encodeWithType(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            if self is RayLaser {
                try container.encode(LaserType.ray, forKey: .type)
            } else if self is SegmentLaser {
                try container.encode(LaserType.segment, forKey: .type)
            }

            try encode(to: encoder)
        }
    }

    final class RayLaser: Laser {
        let endpoint: EndpointPath
        /// Initial angle in radians. Computed at load time: perpendicular to path for moving endpoints, 0 for stationary.
        let initialAngle: Double
        /// Rotation speed in radians per second.
        let rotationSpeed: Double

        private enum CodingKeys: String, CodingKey {
            case endpoint
            case initialAngle
            case rotationSpeed
        }

        init(id: String, color: String, thickness: CGFloat, cadence: [CadenceStep]?,
             endpoint: EndpointPath, initialAngle: Double?, rotationSpeed: Double, enabled: Bool = true) {
            self.endpoint = endpoint
            // Compute default if not provided
            self.initialAngle = initialAngle ?? Self.computeDefaultAngle(for: endpoint)
            self.rotationSpeed = rotationSpeed
            super.init(id: id, color: color, thickness: thickness, cadence: cadence, enabled: enabled)
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            endpoint = try container.decode(EndpointPath.self, forKey: .endpoint)
            let explicitAngle = try container.decodeIfPresent(Double.self, forKey: .initialAngle)
            // Compute default at decode time if not specified
            initialAngle = explicitAngle ?? Self.computeDefaultAngle(for: endpoint)
            rotationSpeed = try container.decode(Double.self, forKey: .rotationSpeed)
            try super.init(from: decoder)
        }

        override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(endpoint, forKey: .endpoint)
            try container.encode(initialAngle, forKey: .initialAngle)
            try container.encode(rotationSpeed, forKey: .rotationSpeed)
        }

        override func isEqual(to other: Laser) -> Bool {
            guard let otherRay = other as? RayLaser else { return false }
            return super.isEqual(to: other) &&
                   endpoint == otherRay.endpoint &&
                   initialAngle == otherRay.initialAngle &&
                   rotationSpeed == otherRay.rotationSpeed
        }

        override func hash(into hasher: inout Hasher) {
            super.hash(into: &hasher)
            hasher.combine(endpoint)
            hasher.combine(initialAngle)
            hasher.combine(rotationSpeed)
        }

        /// Compute the default initial angle based on the endpoint path.
        /// For moving endpoints, returns the perpendicular angle to the path direction.
        /// For stationary endpoints, returns 0.
        private static func computeDefaultAngle(for endpoint: EndpointPath) -> Double {
            // Default: 0 for stationary, perpendicular to path for moving
            if endpoint.isStationary {
                return 0.0
            } else if endpoint.points.count >= 2 {
                let p0 = endpoint.points[0]
                let p1 = endpoint.points[1]
                let dx = p1.x - p0.x
                let dy = p1.y - p0.y
                // Beam is drawn vertically: from (0, -len/2) to (0, +len/2)
                // zRotation=0 → beam vertical, zRotation=π/2 → beam horizontal
                // For perpendicular to path: beam angle = path angle
                // Path going right (0°) → beam vertical (rotation=0°)
                // Path going up (90°) → beam horizontal (rotation=90°)
                return atan2(dy, dx)
            }
            return 0.0
        }
    }

    final class SegmentLaser: Laser {
        let startEndpoint: EndpointPath
        let endEndpoint: EndpointPath

        private enum CodingKeys: String, CodingKey {
            case startEndpoint
            case endEndpoint
        }

        init(id: String, color: String, thickness: CGFloat, cadence: [CadenceStep]?,
             startEndpoint: EndpointPath, endEndpoint: EndpointPath, enabled: Bool = true) {
            self.startEndpoint = startEndpoint
            self.endEndpoint = endEndpoint
            super.init(id: id, color: color, thickness: thickness, cadence: cadence, enabled: enabled)
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            startEndpoint = try container.decode(EndpointPath.self, forKey: .startEndpoint)
            endEndpoint = try container.decode(EndpointPath.self, forKey: .endEndpoint)
            try super.init(from: decoder)
        }

        override func encode(to encoder: Encoder) throws {
            try super.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(startEndpoint, forKey: .startEndpoint)
            try container.encode(endEndpoint, forKey: .endEndpoint)
        }

        override func isEqual(to other: Laser) -> Bool {
            guard let otherSeg = other as? SegmentLaser else { return false }
            return super.isEqual(to: other) &&
                   startEndpoint == otherSeg.startEndpoint &&
                   endEndpoint == otherSeg.endEndpoint
        }

        override func hash(into hasher: inout Hasher) {
            super.hash(into: &hasher)
            hasher.combine(startEndpoint)
            hasher.combine(endEndpoint)
        }
    }
    
    let id: String
    let title: String
    let description: String
    let maxTouches: Int?
    let lives: Int?
    let devices: [Device]?
    let buttons: [Button]
    let lasers: [Laser]
    let unlocks: [String]?
    let backgroundImage: String?
    var uuid: UUID?
    private(set) var directory: URL?
    
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case maxTouches
        case lives
        case devices
        case buttons
        case lasers
        case unlocks
        case backgroundImage
        case uuid
    }
    
    init(
        id: String,
        title: String,
        description: String,
        maxTouches: Int?,
        lives: Int?,
        devices: [Device]?,
        buttons: [Button],
        lasers: [Laser],
        unlocks: [String]?,
        backgroundImage: String?,
        uuid: UUID? = nil,
        directory: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.maxTouches = maxTouches
        self.lives = lives
        self.devices = devices
        self.buttons = buttons
        self.lasers = lasers
        self.unlocks = unlocks
        self.backgroundImage = backgroundImage
        self.uuid = uuid
        self.directory = directory
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        maxTouches = try container.decodeIfPresent(Int.self, forKey: .maxTouches)
        lives = try container.decodeIfPresent(Int.self, forKey: .lives)
        devices = try container.decodeIfPresent([Device].self, forKey: .devices)
        buttons = try container.decode([Button].self, forKey: .buttons)

        // Decode lasers using factory method
        var lasersContainer = try container.nestedUnkeyedContainer(forKey: .lasers)
        var decodedLasers: [Laser] = []
        while !lasersContainer.isAtEnd {
            let laserDecoder = try lasersContainer.superDecoder()
            let laser = try Laser.decode(from: laserDecoder)
            decodedLasers.append(laser)
        }
        lasers = decodedLasers

        unlocks = try container.decodeIfPresent([String].self, forKey: .unlocks)
        backgroundImage = try container.decodeIfPresent(String.self, forKey: .backgroundImage)
        uuid = try container.decodeIfPresent(UUID.self, forKey: .uuid)
        directory = nil
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(maxTouches, forKey: .maxTouches)
        try container.encodeIfPresent(lives, forKey: .lives)
        try container.encodeIfPresent(devices, forKey: .devices)
        try container.encode(buttons, forKey: .buttons)

        // Encode lasers with type discrimination
        var lasersContainer = container.nestedUnkeyedContainer(forKey: .lasers)
        for laser in lasers {
            let laserEncoder = lasersContainer.superEncoder()
            try laser.encodeWithType(to: laserEncoder)
        }

        try container.encodeIfPresent(unlocks, forKey: .unlocks)
        try container.encodeIfPresent(backgroundImage, forKey: .backgroundImage)
        try container.encodeIfPresent(uuid, forKey: .uuid)
    }
}

extension Level {
    func supports(_ device: DeviceProfile.Kind) -> Bool {
        guard let devices = devices, !devices.isEmpty else { return true }
        return devices.contains { $0.rawValue == device.rawValue }
    }
    
    mutating func setDirectory(_ url: URL) {
        directory = url
    }
    
    mutating func setUUID(_ uuid: UUID?) {
        self.uuid = uuid
    }
}

extension Level.Button {
    private enum CodingKeys: String, CodingKey {
        case id
        case position
        case timing
        case hitLogic
        case required
        case color
        case hitAreas
        case effects
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        position = try container.decode(Level.NormalizedPoint.self, forKey: .position)
        timing = try container.decode(Level.Button.Timing.self, forKey: .timing)
        hitLogic = try container.decode(Level.Button.HitLogic.self, forKey: .hitLogic)
        required = try container.decode(Bool.self, forKey: .required)
        color = try container.decode(Level.Button.ColorSpec.self, forKey: .color)
        hitAreas = try container.decode([Level.Button.HitArea].self, forKey: .hitAreas)
        effects = try container.decodeIfPresent([Level.Button.Effect].self, forKey: .effects) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(position, forKey: .position)
        try container.encode(timing, forKey: .timing)
        try container.encode(hitLogic, forKey: .hitLogic)
        try container.encode(required, forKey: .required)
        try container.encode(color, forKey: .color)
        try container.encode(hitAreas, forKey: .hitAreas)
        if !effects.isEmpty {
            try container.encode(effects, forKey: .effects)
        }
    }
}

extension Level.Button.HitArea.Shape: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case radius
        case width
        case height
        case cornerRadius
        case length
        case points
    }
    
    private enum ShapeType: String, Codable {
        case circle
        case rectangle
        case capsule
        case polygon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ShapeType.self, forKey: .type)
        switch type {
        case .circle:
            let radius = try container.decode(CGFloat.self, forKey: .radius)
            self = .circle(radius: radius)
        case .rectangle:
            let width = try container.decode(CGFloat.self, forKey: .width)
            let height = try container.decode(CGFloat.self, forKey: .height)
            let cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)
            self = .rectangle(width: width, height: height, cornerRadius: cornerRadius)
        case .capsule:
            let length = try container.decode(CGFloat.self, forKey: .length)
            let radius = try container.decode(CGFloat.self, forKey: .radius)
            self = .capsule(length: length, radius: radius)
        case .polygon:
            let points = try container.decode([Level.NormalizedPoint].self, forKey: .points)
            self = .polygon(points: points)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .circle(let radius):
            try container.encode(ShapeType.circle, forKey: .type)
            try container.encode(radius, forKey: .radius)
        case .rectangle(let width, let height, let cornerRadius):
            try container.encode(ShapeType.rectangle, forKey: .type)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encodeIfPresent(cornerRadius, forKey: .cornerRadius)
        case .capsule(let length, let radius):
            try container.encode(ShapeType.capsule, forKey: .type)
            try container.encode(length, forKey: .length)
            try container.encode(radius, forKey: .radius)
        case .polygon(let points):
            try container.encode(ShapeType.polygon, forKey: .type)
            try container.encode(points, forKey: .points)
        }
    }
}

