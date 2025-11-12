import Foundation

enum HapticEvent {
    case warning
    case zap
    case death
    case success
}

#if os(iOS)
import CoreHaptics

final class Haptics {
    static let shared = Haptics()
    
    private let engine: CHHapticEngine?
    private lazy var warningEvents: [CHHapticEvent]? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let tap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.25),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
            ],
            relativeTime: 0
        )
        let fade = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ],
            relativeTime: 0,
            duration: 0.05
        )
        return [tap, fade]
    }()
    
    private lazy var zapEvents: [CHHapticEvent]? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let transient = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
            ],
            relativeTime: 0
        )
        let sustain = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ],
            relativeTime: 0,
            duration: 0.15
        )
        let rumble = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ],
            relativeTime: 0.1,
            duration: 0.2
        )
        return [transient, sustain, rumble]
    }()
    
    private lazy var deathEvents: [CHHapticEvent]? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let smash = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9)
            ],
            relativeTime: 0
        )
        let surge = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ],
            relativeTime: 0,
            duration: 0.25
        )
        let rumble = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
            ],
            relativeTime: 0.18,
            duration: 0.4
        )
        let snap = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
            ],
            relativeTime: 0.5
        )
        return [smash, surge, rumble, snap]
    }()
    
    private lazy var successEvents: [CHHapticEvent]? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let lift = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            ],
            relativeTime: 0
        )
        let sparkle = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ],
            relativeTime: 0.05
        )
        return [lift, sparkle]
    }()
    
    private init() {
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
        } else {
            engine = nil
        }
    }
    
    func play(_ event: HapticEvent) {
        guard let engine, let events = events(for: event) else { return }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            #if DEBUG
            print("Haptics error (\(event)):", error)
            #endif
        }
    }
    
    private func events(for event: HapticEvent) -> [CHHapticEvent]? {
        switch event {
        case .warning:
            return warningEvents
        case .zap:
            return zapEvents
        case .death:
            return deathEvents
        case .success:
            return successEvents
        }
    }
}
#else
final class Haptics {
    static let shared = Haptics()
    private init() {}
    func play(_ event: HapticEvent) {}
}
#endif
