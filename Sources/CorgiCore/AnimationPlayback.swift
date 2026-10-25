import Foundation

/// Animation operations used by the presentation policy, independent of the rendering framework.
public protocol AnimationPlaybackBackend: AnyObject {
    func play(_ state: AnimState)
    /// Plays one resolved cycle, even if its manifest loops, and reports the actual duration.
    /// Returns nil when unsupported. Replacing playback cancels its completion.
    @discardableResult
    func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval?
}

extension AnimationPlaybackBackend {
    public func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval? { nil }
}

/// Owns temporary poses without letting old completions replace a newer physical or behavior state.
public final class AnimationPlayback {
    private struct Reaction {
        let id: UInt64
        let state: AnimState
        let mode: BodyMode
        var remaining: TimeInterval
    }

    private let backend: any AnimationPlaybackBackend
    private var reaction: Reaction?
    private var nextID: UInt64 = 0
    public private(set) var currentState: AnimState?
    public var reactionState: AnimState? { reaction?.state }

    public init(backend: any AnimationPlaybackBackend) { self.backend = backend }

    @discardableResult
    public func requestReaction(_ state: AnimState, mode: BodyMode) -> Bool {
        reconcile(mode: mode)
        switch (state, mode) {
        case (.land, .grounded), (.happy, .grounded), (.wiggle, .grounded), (.letGo, .airborne): break
        default: return false
        }
        if reaction?.state == state { return true }
        // Hover/click feedback must not cut a landing short.
        if reaction?.state == .land { return false }

        nextID &+= 1
        let id = nextID
        // Install ownership before calling a backend: completion may be synchronous.
        reaction = Reaction(id: id, state: state, mode: mode, remaining: .infinity)
        currentState = state
        let duration = backend.playOnce(state) { [weak self] in self?.finish(id: id) }
        guard reaction?.id == id else { return true }
        guard let duration, duration.isFinite, duration > 0 else {
            finish(id: id)
            return false
        }
        // Completion is authoritative. This grace period only recovers a missing callback.
        // It advances with controller time, so screen pause does not consume it.
        let timeout = duration + max(1, duration * 0.25)
        guard timeout.isFinite else {
            finish(id: id)
            return false
        }
        reaction?.remaining = timeout
        return true
    }

    public func advance(dt: TimeInterval, mode: BodyMode) {
        reconcile(mode: mode)
        guard dt.isFinite, dt > 0, var active = reaction else { return }
        active.remaining -= dt
        reaction = active
        if active.remaining <= 0 { finish(id: active.id) }
    }

    public func cancelReaction() {
        guard reaction != nil else { return }
        reaction = nil
        currentState = nil
    }

    /// Pause only the grounded behavior clock and its locomotion command, never gravity.
    public func holdsGroundedMotion(in mode: BodyMode) -> Bool {
        mode == .grounded && reaction?.mode == .grounded
    }

    public func update(_ state: AnimState, mode: BodyMode) {
        reconcile(mode: mode)
        guard reaction == nil, state != currentState else { return }
        currentState = state
        backend.play(state)
    }

    private func reconcile(mode: BodyMode) {
        if let reaction, reaction.mode != mode { cancelReaction() }
    }

    private func finish(id: UInt64) {
        guard reaction?.id == id else { return }
        cancelReaction()
    }
}
