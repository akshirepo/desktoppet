import Foundation

/// Cursor resting on the corgi pets it after `delay`, then again every `repeatEvery`.
public final class HoverPet {
    public var delay: TimeInterval = 0.4
    public var repeatEvery: TimeInterval = 1.5
    private var hovered: TimeInterval = 0
    private var nextPetAt: TimeInterval = 0

    public init() {}

    /// - Parameter blocked: dragging, held, roaming, or asleep. Blocked hover never pets and resets the timer.
    /// - Returns: true when a pet should happen now (the caller still applies the rate limit).
    public func update(dt: TimeInterval, hovering: Bool, blocked: Bool) -> Bool {
        guard hovering && !blocked else {
            hovered = 0
            nextPetAt = delay
            return false
        }
        if hovered == 0 { nextPetAt = delay }
        hovered += dt
        guard hovered >= nextPetAt else { return false }
        nextPetAt += repeatEvery
        return true
    }
}

/// Bored after `threshold` seconds with no interaction, while happy and rested enough to play.
public final class BoredomTimer {
    public var threshold: TimeInterval = 600
    public var minHappiness = 50.0
    public var minEnergy = 40.0
    let clock: Clock
    private var lastInteraction: Date

    public init(clock: Clock) {
        self.clock = clock
        lastInteraction = clock.now
    }

    /// Pets, drags, catches, menu care actions, and starting a ball chase all count.
    public func noteInteraction() {
        lastInteraction = clock.now
    }

    public var secondsSinceInteraction: TimeInterval {
        max(0, clock.now.timeIntervalSince(lastInteraction))
    }

    public func isBored(_ needs: NeedsState) -> Bool {
        secondsSinceInteraction >= threshold && needs.happiness > minHappiness && needs.energy > minEnergy
    }
}
