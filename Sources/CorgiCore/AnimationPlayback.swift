import Foundation

/// Animation operations used by the presentation policy, independent of the rendering framework.
public protocol AnimationPlaybackBackend: AnyObject {
    func play(_ state: AnimState)
    /// Plays one resolved cycle, even if its manifest loops, and reports the actual duration.
    /// Returns nil when unsupported. Replacing playback cancels its completion.
    @discardableResult
    func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval?
    /// Seconds until the current loop reaches its next 1/`parts` mark (the next footfall of a walk,
    /// the end of a bite). Nil when unknown.
    func timeToCycleBoundary(parts: Int) -> TimeInterval?
    /// Plays a named bridge animation once (see `Bridge`). Returns nil when the pack doesn't have it.
    @discardableResult
    func playBridge(_ name: String, completion: @escaping () -> Void) -> TimeInterval?
}

extension AnimationPlaybackBackend {
    public func playOnce(_ state: AnimState, completion: @escaping () -> Void) -> TimeInterval? { nil }
    public func timeToCycleBoundary(parts: Int) -> TimeInterval? { nil }
    public func playBridge(_ name: String, completion: @escaping () -> Void) -> TimeInterval? { nil }
}

/// Owns temporary poses without letting old completions replace a newer physical or behavior state.
public final class AnimationPlayback {
    private struct Reaction {
        let id: UInt64
        let state: AnimState
        let mode: BodyMode
        var remaining: TimeInterval
    }

    private struct Transition {
        let target: AnimState
        var steps: [TransitionStep]
        /// Changes with every step, so a late completion from an earlier step is ignored.
        var token: UInt64
        var remaining: TimeInterval
        var current: TransitionStep?
    }

    private let backend: any AnimationPlaybackBackend
    private var reaction: Reaction?
    private var transition: Transition?
    private var nextID: UInt64 = 0
    public private(set) var currentState: AnimState?
    public var reactionState: AnimState? { reaction?.state }
    /// The loop it's on its way to while in-between poses play.
    public var transitionTarget: AnimState? { transition?.target }
    public var graph: TransitionGraph
    /// Called with each routing decision, for debugging.
    public var trace: ((String) -> Void)?

    /// Standing or roaming toward the cursor, poses go through bridges; in the air, held or clinging they switch directly.
    static func routes(_ mode: BodyMode) -> Bool { mode == .grounded || mode == .roaming }

    public init(backend: any AnimationPlaybackBackend, graph: TransitionGraph = .init()) {
        self.backend = backend
        self.graph = graph
    }

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
        transition = nil

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
        guard dt.isFinite, dt > 0 else { return }
        if var active = reaction {
            active.remaining -= dt
            reaction = active
            if active.remaining <= 0 { finish(id: active.id) }
            return
        }
        if var t = transition {
            t.remaining -= dt
            transition = t
            if t.remaining <= 0 { nextStep(token: t.token) }
        }
    }

    public func cancelReaction() {
        guard let r = reaction else { return }
        reaction = nil
        currentState = settledPose(after: r.state)
    }

    /// The pose a reaction leaves it in, so the next change still routes through bridges:
    /// a landing or a wiggle ends standing, a happy hop ends sitting. In the air there's no pose to route from.
    private func settledPose(after state: AnimState) -> AnimState? {
        if state == .letGo { return nil }
        return graph.hub(state) ?? .idle
    }

    /// Pause only the grounded behavior clock and its locomotion command, never gravity.
    /// Also true while a one-shot step (sitting down, getting up, a yawn) plays, so it doesn't slide.
    public func holdsGroundedMotion(in mode: BodyMode) -> Bool {
        guard mode == .grounded || mode == .roaming else { return false }
        if mode == .grounded && reaction?.mode == .grounded { return true }
        switch transition?.current {
        case .once?, .bridge?: return true
        default: return false
        }
    }

    /// Show `state` as the looping animation, going through in-between poses when the posture changes.
    public func update(_ state: AnimState, mode: BodyMode) {
        reconcile(mode: mode)
        guard reaction == nil else { return }
        if let t = transition {
            guard t.target != state else { return }
            // Changed its mind halfway: plan again from the pose on screen.
            transition = nil
        } else if state == currentState {
            return
        }
        let steps = Self.routes(mode) ? currentState.map { graph.plan(from: $0, to: state) } ?? [] : []
        trace?("\(currentState?.rawValue ?? "nil") -> \(state.rawValue) mode=\(mode) steps=\(steps)")
        guard !steps.isEmpty else {
            currentState = state
            backend.play(state)
            return
        }
        transition = Transition(target: state, steps: steps, token: 0, remaining: 0)
        nextStep(token: 0)
    }

    private func nextStep(token: UInt64) {
        guard var t = transition, t.token == token else { return }
        nextID &+= 1
        t.token = nextID
        guard !t.steps.isEmpty else {
            transition = nil
            currentState = t.target
            backend.play(t.target)
            return
        }
        let step = t.steps.removeFirst()
        t.current = step
        let mine = t.token
        switch step {
        case .finish(let s):
            // The loop already on screen keeps going until its next natural break.
            let wait = currentState == s ? backend.timeToCycleBoundary(parts: graph.finishParts[s.base] ?? 1) ?? 0 : 0
            t.remaining = wait.isFinite ? wait : 0
            transition = t
            if t.remaining <= 0 { nextStep(token: mine) }
        case .hold(let s, let seconds):
            t.remaining = seconds
            transition = t
            currentState = s
            backend.play(s)
        case .once, .bridge:
            t.remaining = .infinity
            transition = t
            currentState = step.state
            let done: () -> Void = { [weak self] in self?.nextStep(token: mine) }
            let duration: TimeInterval?
            if case .bridge(let name, _) = step { duration = backend.playBridge(name, completion: done) }
            else { duration = backend.playOnce(step.state, completion: done) }
            guard transition?.token == mine else { return }   // finished synchronously
            guard let duration, duration.isFinite, duration > 0 else {
                nextStep(token: mine)
                return
            }
            // Completion is authoritative; this only recovers a lost callback.
            transition?.remaining = duration + max(1, duration * 0.25)
        }
    }

    private func reconcile(mode: BodyMode) {
        if let reaction, reaction.mode != mode { cancelReaction() }
        if transition != nil && !Self.routes(mode) { transition = nil }
    }

    private func finish(id: UInt64) {
        guard reaction?.id == id else { return }
        cancelReaction()
    }
}
