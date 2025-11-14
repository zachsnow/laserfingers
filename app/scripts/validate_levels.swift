#!/usr/bin/env swift

import Foundation

// Add the app's source directory to be able to import Level types
// This script validates levels using the actual Codable types from the app

// MARK: - Copy of Level types for validation

struct NormalizedPoint: Codable {
    let x: Double
    let y: Double
}

struct EndpointPath: Codable {
    let points: [NormalizedPoint]
    let cycleSeconds: Double?
    let t: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode([NormalizedPoint].self, forKey: .points)
        cycleSeconds = try container.decodeIfPresent(Double.self, forKey: .cycleSeconds)
        t = try container.decodeIfPresent(Double.self, forKey: .t) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case cycleSeconds
        case t
    }
}

struct CadenceStep: Codable {
    let onSeconds: Double
    let offSeconds: Double
}

struct HitArea: Codable {
    enum Shape: Codable {
        case circle(radius: Double)
        case rectangle(width: Double, height: Double)
        case capsule(width: Double, height: Double)
        case polygon(points: [NormalizedPoint])

        private enum CodingKeys: String, CodingKey {
            case type
            case radius
            case width
            case height
            case points
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)

            switch type {
            case "circle":
                let radius = try container.decode(Double.self, forKey: .radius)
                self = .circle(radius: radius)
            case "rectangle":
                let width = try container.decode(Double.self, forKey: .width)
                let height = try container.decode(Double.self, forKey: .height)
                self = .rectangle(width: width, height: height)
            case "capsule":
                let width = try container.decode(Double.self, forKey: .width)
                let height = try container.decode(Double.self, forKey: .height)
                self = .capsule(width: width, height: height)
            case "polygon":
                let points = try container.decode([NormalizedPoint].self, forKey: .points)
                self = .polygon(points: points)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown shape type: \(type)")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .circle(let radius):
                try container.encode("circle", forKey: .type)
                try container.encode(radius, forKey: .radius)
            case .rectangle(let width, let height):
                try container.encode("rectangle", forKey: .type)
                try container.encode(width, forKey: .width)
                try container.encode(height, forKey: .height)
            case .capsule(let width, let height):
                try container.encode("capsule", forKey: .type)
                try container.encode(width, forKey: .width)
                try container.encode(height, forKey: .height)
            case .polygon(let points):
                try container.encode("polygon", forKey: .type)
                try container.encode(points, forKey: .points)
            }
        }
    }

    let id: String
    let shape: Shape
    let offset: NormalizedPoint
    let rotationDegrees: Double?
}

struct ColorSpec: Codable {
    let fill: String
    let glow: String?
    let rim: String?
}

struct Timing: Codable {
    let chargeSeconds: Double
    let holdSeconds: Double?
    let drainSeconds: Double
}

struct Effect: Codable {
    enum Trigger: String, Codable {
        case touchStarted
        case touchEnded
        case turnedOn
        case turnedOff
    }

    struct Action: Codable {
        enum Kind: String, Codable {
            case turnOnLasers
            case turnOffLasers
            case toggleLasers
        }

        let kind: Kind
        let lasers: [String]
    }

    let trigger: Trigger
    let action: Action
}

struct Button: Codable {
    enum HitLogic: String, Codable {
        case any = "any"
        case all = "all"
    }

    let id: String
    let endpoints: [EndpointPath]
    let timing: Timing
    let hitLogic: HitLogic
    let required: Bool
    let color: ColorSpec
    let hitAreas: [HitArea]
    let effects: [Effect]
}

class Laser: Codable {
    let id: String
    let color: String
    let thickness: Double
    let cadence: [CadenceStep]?
    let enabled: Bool
    var endpoints: [EndpointPath]

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case color
        case thickness
        case cadence
        case enabled
        case endpoints
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        color = try container.decode(String.self, forKey: .color)
        thickness = try container.decode(Double.self, forKey: .thickness)
        cadence = try container.decodeIfPresent([CadenceStep].self, forKey: .cadence)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        endpoints = try container.decode([EndpointPath].self, forKey: .endpoints)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(color, forKey: .color)
        try container.encode(thickness, forKey: .thickness)
        try container.encodeIfPresent(cadence, forKey: .cadence)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(endpoints, forKey: .endpoints)
    }
}

class RayLaser: Laser {
    let initialAngle: Double
    let rotationSpeed: Double

    private enum CodingKeys: String, CodingKey {
        case endpoints
        case initialAngle
        case rotationSpeed
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEndpoints = try container.decode([EndpointPath].self, forKey: .endpoints)

        self.initialAngle = try container.decodeIfPresent(Double.self, forKey: .initialAngle) ?? 0
        self.rotationSpeed = try container.decode(Double.self, forKey: .rotationSpeed)

        try super.init(from: decoder)
        self.endpoints = decodedEndpoints
    }

    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoints, forKey: .endpoints)
        try container.encode(initialAngle, forKey: .initialAngle)
        try container.encode(rotationSpeed, forKey: .rotationSpeed)
    }
}

class SegmentLaser: Laser {
    private enum CodingKeys: String, CodingKey {
        case endpoints
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEndpoints = try container.decode([EndpointPath].self, forKey: .endpoints)
        try super.init(from: decoder)
        self.endpoints = decodedEndpoints

        guard endpoints.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .endpoints, in: container, debugDescription: "SegmentLaser must have exactly 2 endpoints, got \(endpoints.count)")
        }
    }

    override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoints, forKey: .endpoints)
    }
}

struct Level: Codable {
    enum Device: String, Codable {
        case iPhone = "iPhone"
        case iPad = "iPad"
        case iPadMini = "iPad Mini"
    }

    let id: String
    let title: String
    let description: String
    let backgroundImage: String?
    let devices: [Device]?
    let maxTouches: Int?
    let buttons: [Button]
    let lasers: [Laser]
    let unlocks: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case backgroundImage
        case devices
        case maxTouches
        case buttons
        case lasers
        case unlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        backgroundImage = try container.decodeIfPresent(String.self, forKey: .backgroundImage)
        devices = try container.decodeIfPresent([Device].self, forKey: .devices)
        maxTouches = try container.decodeIfPresent(Int.self, forKey: .maxTouches)
        buttons = try container.decode([Button].self, forKey: .buttons)
        unlocks = try container.decode([String].self, forKey: .unlocks)

        // Decode lasers polymorphically
        var lasersArray = try container.nestedUnkeyedContainer(forKey: .lasers)
        var decodedLasers: [Laser] = []

        while !lasersArray.isAtEnd {
            // Peek at the type using a temporary container
            let decoder = try lasersArray.superDecoder()
            let laserContainer = try decoder.container(keyedBy: LaserTypeKeys.self)
            let type = try laserContainer.decode(String.self, forKey: .type)

            switch type {
            case "ray":
                let rayLaser = try RayLaser(from: decoder)
                decodedLasers.append(rayLaser)
            case "segment":
                let segmentLaser = try SegmentLaser(from: decoder)
                decodedLasers.append(segmentLaser)
            default:
                throw DecodingError.dataCorruptedError(in: lasersArray, debugDescription: "Unknown laser type: \(type)")
            }
        }

        self.lasers = decodedLasers
    }

    private enum LaserTypeKeys: String, CodingKey {
        case type
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(backgroundImage, forKey: .backgroundImage)
        try container.encodeIfPresent(devices, forKey: .devices)
        try container.encodeIfPresent(maxTouches, forKey: .maxTouches)
        try container.encode(buttons, forKey: .buttons)
        try container.encode(unlocks, forKey: .unlocks)

        var lasersContainer = container.nestedUnkeyedContainer(forKey: .lasers)
        for laser in lasers {
            if let rayLaser = laser as? RayLaser {
                try lasersContainer.encode(rayLaser)
            } else if let segmentLaser = laser as? SegmentLaser {
                try lasersContainer.encode(segmentLaser)
            }
        }
    }
}

// MARK: - Validation Logic

func validateLevel(at path: String) -> (valid: Bool, errors: [String]) {
    var errors: [String] = []

    // Try to read the file
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        return (false, ["Failed to read file"])
    }

    // Try to decode as Level
    let decoder = JSONDecoder()
    do {
        let level = try decoder.decode(Level.self, from: data)

        // Additional semantic validation

        // Check for at least one button (except for menu/background levels)
        if level.buttons.isEmpty && !level.id.contains("menu") && !level.id.contains("background") {
            errors.append("Level has no buttons")
        }

        // Validate button IDs are unique
        let buttonIDs = level.buttons.map { $0.id }
        if Set(buttonIDs).count != buttonIDs.count {
            errors.append("Duplicate button IDs found")
        }

        // Validate laser IDs are unique
        let laserIDs = level.lasers.map { $0.id }
        if Set(laserIDs).count != laserIDs.count {
            errors.append("Duplicate laser IDs found")
        }

        // Validate buttons have at least one endpoint
        for button in level.buttons {
            if button.endpoints.isEmpty {
                errors.append("Button '\(button.id)' has no endpoints")
            }
            if button.hitAreas.isEmpty {
                errors.append("Button '\(button.id)' has no hit areas")
            }
        }

        // Validate ray lasers have exactly 1 endpoint
        for laser in level.lasers {
            if laser is RayLaser {
                if laser.endpoints.count != 1 {
                    errors.append("Ray laser '\(laser.id)' must have exactly 1 endpoint, has \(laser.endpoints.count)")
                }
            }
        }

        // Validate segment lasers have exactly 2 endpoints
        for laser in level.lasers {
            if laser is SegmentLaser {
                if laser.endpoints.count != 2 {
                    errors.append("Segment laser '\(laser.id)' must have exactly 2 endpoints, has \(laser.endpoints.count)")
                }
            }
        }

        // Validate effect target IDs exist
        for button in level.buttons {
            for effect in button.effects {
                for laserID in effect.action.lasers {
                    let targetExists = level.lasers.contains { $0.id == laserID }
                    if !targetExists {
                        errors.append("Button '\(button.id)' has effect targeting non-existent laser '\(laserID)'")
                    }
                }
            }
        }

        return (errors.isEmpty, errors)

    } catch let decodingError as DecodingError {
        switch decodingError {
        case .dataCorrupted(let context):
            errors.append("Data corrupted: \(context.debugDescription)")
        case .keyNotFound(let key, let context):
            errors.append("Missing key '\(key.stringValue)': \(context.debugDescription)")
        case .typeMismatch(let type, let context):
            errors.append("Type mismatch for \(type): \(context.debugDescription)")
        case .valueNotFound(let type, let context):
            errors.append("Value not found for \(type): \(context.debugDescription)")
        @unknown default:
            errors.append("Decoding error: \(decodingError)")
        }
        return (false, errors)
    } catch {
        return (false, ["Unexpected error: \(error)"])
    }
}

// MARK: - Main Script

func main() {
    let levelsDir = "app/Laserfingers/Levels"
    let fileManager = FileManager.default

    guard let enumerator = fileManager.enumerator(atPath: levelsDir) else {
        print("Error: Could not enumerate levels directory")
        exit(1)
    }

    var allFiles: [String] = []
    while let path = enumerator.nextObject() as? String {
        if path.hasSuffix(".json") {
            allFiles.append("\(levelsDir)/\(path)")
        }
    }

    if allFiles.isEmpty {
        print("No level files found")
        exit(0)
    }

    print("Validating \(allFiles.count) level files...\n")

    var validCount = 0
    var invalidCount = 0

    for filePath in allFiles.sorted() {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        let result = validateLevel(at: filePath)

        if result.valid {
            print("✓ \(fileName)")
            validCount += 1
        } else {
            print("✗ \(fileName)")
            for error in result.errors {
                print("  - \(error)")
            }
            invalidCount += 1
        }
    }

    print("\n" + String(repeating: "=", count: 50))
    print("Validation complete:")
    print("  ✓ Valid: \(validCount)")
    if invalidCount > 0 {
        print("  ✗ Invalid: \(invalidCount)")
        exit(1)
    }
}

main()
