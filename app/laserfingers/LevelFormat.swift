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
    
    struct Laser: Identifiable, Codable, Hashable {
        struct CadenceStep: Codable, Hashable {
            enum State: String, Codable {
                case on
                case off
            }
            
            let state: State
            /// Duration to stay in the given state. Nil = hold indefinitely.
            let duration: Double?
        }
        
        enum Kind: Hashable {
            case sweeper(Sweeper)
            case rotor(Rotor)
            case segment(Segment)
        }
        
        struct Sweeper: Codable, Hashable {
            /// Normalized endpoints measured in the short-axis coordinate space.
            let start: NormalizedPoint
            let end: NormalizedPoint
            /// Seconds to travel from start to end before reversing.
            let sweepSeconds: Double
        }
        
        struct Rotor: Codable, Hashable {
            let center: NormalizedPoint
            /// Degrees per second. Positive = clockwise.
            let speedDegreesPerSecond: Double
            let initialAngleDegrees: Double
        }
        
        struct Segment: Codable, Hashable {
            let start: NormalizedPoint
            let end: NormalizedPoint
        }
        
        let id: String
        let color: String
        /// Normalized beam thickness relative to the shortest scene edge.
        let thickness: CGFloat
        /// Cadence applied to the firing state. Nil or empty => always on.
        let cadence: [CadenceStep]?
        let kind: Kind
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
        lasers = try container.decode([Laser].self, forKey: .lasers)
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
        try container.encode(lasers, forKey: .lasers)
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

extension Level.Laser.Kind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case sweeper
        case rotor
        case segment
    }
    
    private enum KindType: String, Codable {
        case sweeper
        case rotor
        case segment
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        switch type {
        case .sweeper:
            let value = try container.decode(Level.Laser.Sweeper.self, forKey: .sweeper)
            self = .sweeper(value)
        case .rotor:
            let value = try container.decode(Level.Laser.Rotor.self, forKey: .rotor)
            self = .rotor(value)
        case .segment:
            let value = try container.decode(Level.Laser.Segment.self, forKey: .segment)
            self = .segment(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sweeper(let sweeper):
            try container.encode(KindType.sweeper, forKey: .type)
            try container.encode(sweeper, forKey: .sweeper)
        case .rotor(let rotor):
            try container.encode(KindType.rotor, forKey: .type)
            try container.encode(rotor, forKey: .rotor)
        case .segment(let segment):
            try container.encode(KindType.segment, forKey: .type)
            try container.encode(segment, forKey: .segment)
        }
    }
}
