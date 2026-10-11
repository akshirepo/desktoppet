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
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var pressPoint: CGPoint?
    private var dragging = false
    private enum FetchPhase { case chasing(returnX: CGFloat), returning }
    private var fetchPhase: FetchPhase?
    private var ball: SKShapeNode?
    let debug = DebugOverlay()
    private var paused = false
    private var lastZzz: CFTimeInterval = 0

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        overlays = OverlayManager(corgiNode: backend.node)
        world = World(provider: CGWindowListProvider(), screens: NSScreen.screens.map(\.visibleFrame))
        let vf = NSScreen.main?.visibleFrame ?? .zero
        body = Body(position: CGPoint(x: vf.midX, y: vf.maxY - 100))
        overlays.input = self
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
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(true)
        }
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(false)
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(true)
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setPaused(false)
        }
    }

    func greet() {
        brain.interrupt(with: .greet, duration: 4)
        beginBehavior(.greet)
        Effects.floatEmoji("👋", on: backend.node, height: backend.size.height)
    }

    func setPaused(_ paused: Bool) {
        guard paused != self.paused else { return }
        self.paused = paused
        overlays.setPaused(paused)
        if paused {
            timer?.invalidate()
            timer = nil
            timerFPS = 0
        } else {
            lastTick = CACurrentMediaTime()
            setRate(30)
        }
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
        Effects.floatEmoji("❗", on: backend.node, height: backend.size.height)
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        if b != .fetch && fetchPhase != nil { clearFetch() }
        if needs.state.isAsleep != (b == .sleep) { needs.setAsleep(b == .sleep) }
        executor.speedScale = needs.isLow(.happiness) ? 0.6 : 1
        executor.begin(b, body: body, world: world, cursor: NSEvent.mouseLocation)
    }

    /// The executor says the current behavior is done.
    func stepFinished() {
        if brain.current == .fetch && advanceFetch() { return }
        brain.finishCurrent()
    }

    func feed() {
        wake()
        brain.interrupt(with: .eat, duration: 4)
        beginBehavior(.eat)
        needs.feed()
        Effects.floatEmoji("🍖", on: backend.node, height: backend.size.height)
    }

    func bath() {
        wake()
        brain.interrupt(with: .bath, duration: 4)
        beginBehavior(.bath)
        needs.bath()
        Effects.floatEmoji("🫧", on: backend.node, height: backend.size.height, count: 5)
    }

    func nap() {
        brain.interrupt(with: .sleep, duration: 120)
        beginBehavior(.sleep)
    }

    func playBall() {
        wake()
        clearFetch()
        guard body.mode == .grounded, let segment = body.standingOn, segment.width > 200,
              let scene = overlays.currentScene else {
            needs.play()
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
            return
        }
        let start = body.position.x
        let roomRight = segment.maxX - 20 - start, roomLeft = start - (segment.minX + 20)
        let rawX = roomRight >= roomLeft ? start + CGFloat.random(in: 100...max(100, roomRight))
                                         : start - CGFloat.random(in: 100...max(100, roomLeft))
        let ballX = min(max(rawX, segment.minX + 20), segment.maxX - 20)
        let landing = overlays.toScene(CGPoint(x: ballX, y: segment.y + 7))
        let launch = overlays.toScene(CGPoint(x: start, y: segment.y + 40))
        let ball = Effects.makeBall()
        ball.position = launch
        scene.addChild(ball)
        let path = CGMutablePath()
        path.move(to: launch)
        path.addQuadCurve(to: landing, control: CGPoint(x: (launch.x + landing.x) / 2, y: launch.y + 160))
        ball.run(.follow(path, asOffset: false, orientToPath: false, duration: 0.7))
        self.ball = ball

        brain.interrupt(with: .fetch, duration: 20)
        beginBehavior(.fetch)
        executor.targetX = ballX
        fetchPhase = .chasing(returnX: start)
    }

    private func wake() {
        if brain.current == .sleep { brain.finishCurrent() }
        if needs.state.isAsleep { needs.setAsleep(false) }
    }

    /// Moves the fetch along. Returns true while fetch still has work to do.
    private func advanceFetch() -> Bool {
        switch fetchPhase {
        case .chasing(let returnX):
            ball?.removeAllActions()
            ball?.removeFromParent()
            if let ball {
                // Hold the ball at the mouth on the side the corgi is about to walk toward.
                ball.position = CGPoint(x: returnX >= body.position.x ? 26 : -26, y: 30)
                backend.node.addChild(ball)
            }
            executor.targetX = returnX
            fetchPhase = .returning
            return true
        case .returning:
            clearFetch()
            needs.play()
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            return false
        case nil:
            return false
        }
    }

    private func clearFetch() {
        ball?.removeFromParent()
        ball = nil
        fetchPhase = nil
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
        if brain.current == .sleep && now - lastZzz > 2 {
            lastZzz = now
            Effects.floatEmoji("💤", on: backend.node, height: backend.size.height * 0.8)
        }
        debug.update(world: world, hitRect: hitRect, behavior: brain.current, overlays: overlays)
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

extension PetController: SceneInputHandler {
    func mouseDown(at global: CGPoint) {
        pressPoint = global
        dragging = false
    }

    func mouseDragged(to global: CGPoint) {
        guard let start = pressPoint else { return }
        if !dragging && hypot(global.x - start.x, global.y - start.y) > 4 {
            dragging = true
            body.pickUp()
            brain.interrupt(with: .dangle, duration: .infinity)
            beginBehavior(.dangle)
        }
        if dragging {
            body.moveHeld(to: CGPoint(x: global.x, y: global.y - backend.size.height * 0.8))
        }
    }

    func mouseUp(at global: CGPoint) {
        defer {
            pressPoint = nil
            dragging = false
        }
        if dragging {
            body.release()
            brain.interrupt(with: .fall, duration: 5)
            beginBehavior(.fall)
        } else if pressPoint != nil {
            pet()
        }
    }

    func rightMouseDown(_ event: NSEvent, in view: NSView) {
        onRightClick?(event, view)
    }

    func pet() {
        if brain.current == .sleep {
            brain.finishCurrent()
            needs.setAsleep(false)
        }
        if needs.pet() {
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
        }
    }
}
#endif
