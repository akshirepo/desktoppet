import Foundation

public enum Need: String, Codable, CaseIterable {
    case hunger, happiness, energy, cleanliness, thirst
}

public struct NeedsConfig: Codable, Equatable {
    public var hungerPerHour = -8.0
    public var happinessPerHour = -5.0
    public var energyAwakePerHour = -6.0
    public var energyAsleepPerHour = 20.0
    public var cleanlinessPerHour = -3.0
    public var thirstPerHour = -10.0
    public var lowThreshold = 30.0
    public var offlineFloor = 15.0
    public var feedAmount = 40.0
    public var petAmount = 5.0
    public var petsPerMinute = 10
    public var playAmount = 25.0
    public var bathAmount = 60.0
    public var drinkAmount = 50.0
    public var catchAmount = 10.0

    public init() {}
    public static let `default` = NeedsConfig()
}

public struct NeedsState: Codable, Equatable {
    public var hunger: Double
    public var happiness: Double
    public var energy: Double
    public var cleanliness: Double
    public var thirst: Double
    public var isAsleep: Bool
    public var careXP: Int
    public var lastSaved: Date
    public var firstMet: Date

    public static func fresh(at date: Date) -> NeedsState {
        NeedsState(hunger: 70, happiness: 70, energy: 70, cleanliness: 70, thirst: 70,
                   isAsleep: false, careXP: 0, lastSaved: date, firstMet: date)
    }

    public init(hunger: Double, happiness: Double, energy: Double, cleanliness: Double, thirst: Double = 70,
                isAsleep: Bool, careXP: Int, lastSaved: Date, firstMet: Date) {
        self.hunger = hunger
        self.happiness = happiness
        self.energy = energy
        self.cleanliness = cleanliness
        self.thirst = thirst
        self.isAsleep = isAsleep
        self.careXP = careXP
        self.lastSaved = lastSaved
        self.firstMet = firstMet
    }

    private enum CodingKeys: String, CodingKey {
        case hunger, happiness, energy, cleanliness, thirst, isAsleep, careXP, lastSaved, firstMet
    }

    /// Saves from before thirst existed load with thirst at 70.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hunger = try c.decode(Double.self, forKey: .hunger)
        happiness = try c.decode(Double.self, forKey: .happiness)
        energy = try c.decode(Double.self, forKey: .energy)
        cleanliness = try c.decode(Double.self, forKey: .cleanliness)
        thirst = try c.decodeIfPresent(Double.self, forKey: .thirst) ?? 70
        isAsleep = try c.decode(Bool.self, forKey: .isAsleep)
        careXP = try c.decode(Int.self, forKey: .careXP)
        lastSaved = try c.decode(Date.self, forKey: .lastSaved)
        firstMet = try c.decode(Date.self, forKey: .firstMet)
    }

    public subscript(need: Need) -> Double {
        get {
            switch need {
            case .hunger: return hunger
            case .happiness: return happiness
            case .energy: return energy
            case .cleanliness: return cleanliness
            case .thirst: return thirst
            }
        }
        set {
            switch need {
            case .hunger: hunger = newValue
            case .happiness: happiness = newValue
            case .energy: energy = newValue
            case .cleanliness: cleanliness = newValue
            case .thirst: thirst = newValue
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
        case .thirst: return config.thirstPerHour
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

    private var petTimes: [Date] = []

    public var level: Int {
        1 + Int((Double(state.careXP) / 10).squareRoot())
    }

    private func restore(_ need: Need, by amount: Double) {
        tick()
        state[need] = min(100, state[need] + amount)
        state.careXP += 1
    }

    public func feed() { restore(.hunger, by: config.feedAmount) }
    public func play() { restore(.happiness, by: config.playAmount) }
    public func bath() { restore(.cleanliness, by: config.bathAmount) }
    public func drink() { restore(.thirst, by: config.drinkAmount) }

    /// Returns false when the per-minute pet limit is reached.
    @discardableResult
    public func pet() -> Bool { rateLimitedHappiness(config.petAmount) }

    /// Catching the corgi in Chase Me. Shares the pet rate limit.
    @discardableResult
    public func catchPet() -> Bool { rateLimitedHappiness(config.catchAmount) }

    private func rateLimitedHappiness(_ amount: Double) -> Bool {
        let now = clock.now
        petTimes.removeAll { now.timeIntervalSince($0) >= 60 || $0 > now }
        guard petTimes.count < config.petsPerMinute else { return false }
        petTimes.append(now)
        restore(.happiness, by: amount)
        return true
    }

    public func setAsleep(_ asleep: Bool) {
        tick()
        state.isAsleep = asleep
    }

    public func markSaved() {
        tick()
        state.lastSaved = clock.now
    }
}
