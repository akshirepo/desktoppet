import Foundation

public enum Need: String, Codable, CaseIterable {
    case hunger, happiness, energy, cleanliness
}

public struct NeedsConfig: Codable, Equatable {
    public var hungerPerHour = -8.0
    public var happinessPerHour = -5.0
    public var energyAwakePerHour = -6.0
    public var energyAsleepPerHour = 20.0
    public var cleanlinessPerHour = -3.0
    public var lowThreshold = 30.0
    public var offlineFloor = 15.0
    public var feedAmount = 40.0
    public var petAmount = 5.0
    public var petsPerMinute = 10
    public var playAmount = 25.0
    public var bathAmount = 60.0

    public init() {}
    public static let `default` = NeedsConfig()
}

public struct NeedsState: Codable, Equatable {
    public var hunger: Double
    public var happiness: Double
    public var energy: Double
    public var cleanliness: Double
    public var isAsleep: Bool
    public var careXP: Int
    public var lastSaved: Date
    public var firstMet: Date

    public static func fresh(at date: Date) -> NeedsState {
        NeedsState(hunger: 70, happiness: 70, energy: 70, cleanliness: 70,
                   isAsleep: false, careXP: 0, lastSaved: date, firstMet: date)
    }

    public subscript(need: Need) -> Double {
        get {
            switch need {
            case .hunger: return hunger
            case .happiness: return happiness
            case .energy: return energy
            case .cleanliness: return cleanliness
            }
        }
        set {
            switch need {
            case .hunger: hunger = newValue
            case .happiness: happiness = newValue
            case .energy: energy = newValue
            case .cleanliness: cleanliness = newValue
            }
        }
    }
}

public final class NeedsEngine {
    public private(set) var state: NeedsState
    public let config: NeedsConfig
    let clock: Clock
    private var lastTick: Date

    public init(state: NeedsState, config: NeedsConfig = .default, clock: Clock) {
        self.state = state
        self.config = config
        self.clock = clock
        self.lastTick = clock.now
    }

    func ratePerHour(_ need: Need, asleep: Bool) -> Double {
        switch need {
        case .hunger: return config.hungerPerHour
        case .happiness: return config.happinessPerHour
        case .energy: return asleep ? config.energyAsleepPerHour : config.energyAwakePerHour
        case .cleanliness: return config.cleanlinessPerHour
        }
    }

    /// Applies decay since `state.lastSaved`, never pushing a need below the offline floor.
    @discardableResult
    public func catchUpOffline() -> TimeInterval {
        let elapsed = max(0, clock.now.timeIntervalSince(state.lastSaved))
        let hours = elapsed / 3600
        for need in Need.allCases {
            let old = state[need]
            let decayed = old + ratePerHour(need, asleep: false) * hours
            state[need] = min(100, max(min(old, config.offlineFloor), decayed))
        }
        lastTick = clock.now
        return elapsed
    }

    public func tick() {
        let now = clock.now
        let hours = max(0, now.timeIntervalSince(lastTick)) / 3600
        lastTick = max(lastTick, now)
        for need in Need.allCases {
            state[need] = min(100, max(0, state[need] + ratePerHour(need, asleep: state.isAsleep) * hours))
        }
    }

    public func isLow(_ need: Need) -> Bool {
        state[need] < config.lowThreshold
    }
}
