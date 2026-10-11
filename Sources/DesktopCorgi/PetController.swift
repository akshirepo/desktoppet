#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

final class PetController {
    let needs: NeedsEngine
    let brain = Brain()
    let executor = BehaviorExecutor()
    let world: World
    let body: Body
    let backend: AnimationBackend
    let overlays: OverlayManager

    var animOverride: (state: AnimState, until: CFTimeInterval)?
    private var currentAnim: AnimState?
    private var timer: Timer?
    private var timerFPS = 0
    private var worldTimer: Timer?
    private var lastTick = CACurrentMediaTime()

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        overlays = OverlayManager(corgiNode: backend.node)
        world = World(provider: CGWindowListProvider(), screens: NSScreen.screens.map(\.visibleFrame))
        let vf = NSScreen.main?.visibleFrame ?? .zero
        body = Body(position: CGPoint(x: vf.midX, y: vf.maxY - 100))
    }

    var hitRect: CGRect {
        CGRect(x: body.position.x - backend.size.width / 2, y: body.position.y,
               width: backend.size.width, height: backend.size.height)
    }

    func start() {
        world.refresh()
        worldTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWorld() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshWorld() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screensChanged() }
        setRate(30)
    }

    private func setRate(_ fps: Int) {
        guard fps != timerFPS else { return }
        timerFPS = fps
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / Double(fps), repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        overlays.setFPS(fps)
    }

    func refreshWorld() {
        if body.apply(world.refresh()) == .startedFalling { fell() }
    }

    func screensChanged() {
        world.setScreens(NSScreen.screens.map(\.visibleFrame))
        overlays.rebuild()
        body.clamp(to: world.screens)
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        if needs.state.isAsleep != (b == .sleep) { needs.setAsleep(b == .sleep) }
        executor.speedScale = needs.isLow(.happiness) ? 0.6 : 1
        executor.begin(b, body: body, world: world, cursor: NSEvent.mouseLocation)
    }

    /// The executor says the current behavior is done.
    func stepFinished() {
        brain.finishCurrent()
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        needs.tick()

        let canHop = !world.reachableSegments(from: body.position, maxJumpUp: body.config.maxJumpUp,
                                              maxJumpAcross: body.config.maxJumpAcross).isEmpty
        let ctx = BrainContext(needs: needs.state, lowThreshold: needs.config.lowThreshold, canHop: canHop)
        if let next = brain.update(dt: dt, ctx) { beginBehavior(next) }

        let cursor = NSEvent.mouseLocation
        if executor.step(brain.current, body: body, world: world, cursor: cursor) { stepFinished() }
        if let event = body.step(dt: dt, world: world) {
            if executor.handle(event, behavior: brain.current, body: body) { stepFinished() }
            if event == .landed {
                animOverride = (.land, now + 0.25)
                if brain.current == .fall { brain.finishCurrent() }
            }
            if event == .startedFalling { fell() }
        }
        body.clamp(to: world.screens)

        overlays.place(globalFeet: body.position)
        backend.setFacing(right: body.facingRight)
        updateAnimation(now)
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor)))
        setRate(body.isMoving || body.mode == .held || animOverride != nil ? 30 : 10)
    }

    private func updateAnimation(_ now: CFTimeInterval) {
        if let o = animOverride, o.until <= now { animOverride = nil }
        let state = animOverride?.state
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving)
        if state != currentAnim {
            currentAnim = state
            backend.play(state)
        }
    }
}
#endif
