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
    private var screenLocked = false
    private var screensAsleep = false
    private var lastZzz: CFTimeInterval = 0
    private var lastSweat: CFTimeInterval = 0
    let home = HomeTracker(clock: SystemClock())
    let rest = RestMonitor()
    let hover = HoverPet()
    private var prop: SKLabelNode?
    private var propEmoji: String?
    private static let props: [Behavior: String] = [
        .read: "📖", .readSleep: "📖", .music: "🎧", .watchTV: "📺", .playBallHome: "⚽️",
    ]

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        overlays = OverlayManager(corgiNode: backend.node)
        world = World(provider: CGWindowListProvider(), screens: NSScreen.screens.map(\.visibleFrame))
        let vf = NSScreen.main?.visibleFrame ?? .zero
        body = Body(position: CGPoint(x: vf.midX, y: vf.maxY - 100))
        overlays.input = self
        updateHome()
    }

    /// Home is on the primary screen (the one with the menu bar), index 0 in `world.screens`.
    private func updateHome() {
        home.setScreens(world.screens, mainIndex: 0)
        executor.home = home.spot
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
            self?.screenLocked = true
            self?.updatePaused()
        }
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.updatePaused()
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.updatePaused()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.updatePaused()
        }
    }

    /// Wave and say hi on every launch; a second bubble if away more than an hour.
    func greet(awaySeconds: TimeInterval) {
        wake()
        let lines = Greeting.lines(awaySeconds: awaySeconds)
        brain.interrupt(with: .greet, duration: lines.count > 1 ? 5.5 : 3)
        beginBehavior(.greet)
        for (i, line) in lines.enumerated() {
            Effects.speech(line, on: backend.node, height: backend.size.height, delay: Double(i) * 2.6)
        }
    }

    /// Stays paused until the screen is both unlocked and awake.
    private func updatePaused() {
        setPaused(screenLocked || screensAsleep)
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
        overlays.setPaused(paused)
        if timerFPS > 0 { overlays.setFPS(timerFPS) }
        body.clamp(to: world.screens)
        updateHome()
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
        Effects.floatEmoji("❗", on: backend.node, height: backend.size.height)
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        if b != .fetch && fetchPhase != nil { clearFetch() }
        if needs.state.isAsleep != b.countsAsSleep { needs.setAsleep(b.countsAsSleep) }
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
        if brain.current.countsAsSleep { brain.finishCurrent() }
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

    /// Seconds since any keyboard or mouse event. Needs no permission.
    private var userIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private var restBusy: Bool {
        dragging || body.mode == .held || body.mode == .roaming || brain.current == .ballChase
    }

    private func updateRest(dt: TimeInterval, now: CFTimeInterval) {
        let fullScreen = isFullScreen(frontWindow: world.windows.first?.frame,
                                      screenFrames: NSScreen.screens.map(\.frame))
        switch rest.update(dt: dt, idleSeconds: userIdleSeconds, fullScreen: fullScreen, busy: restBusy) {
        case .startYawn?:
            brain.interrupt(with: .yawn, duration: .infinity)
            beginBehavior(.yawn)
        case .fallAsleep?:
            brain.interrupt(with: .idleSleep, duration: .infinity)
            beginBehavior(.idleSleep)
        case .wake?:
            if brain.current == .yawn || brain.current == .idleSleep {
                brain.finishCurrent()
                needs.setAsleep(false)
                animOverride = (.wiggle, now + 0.8)
            }
        case nil:
            break
        }
    }

    private func updateHover(dt: TimeInterval, cursor: CGPoint) {
        let blocked = dragging || pressPoint != nil || body.mode != .grounded
            || brain.current.countsAsSleep || brain.current == .yawn
        if hover.update(dt: dt, hovering: hitRect.contains(cursor), blocked: blocked) { hoverPet() }
    }

    private func hoverPet() {
        if needs.pet() {
            Effects.floatEmoji("❤️", on: backend.node, height: backend.size.height, count: 2)
            animOverride = (.happy, CACurrentMediaTime() + 0.8)
        }
    }

    /// Emoji props for idle activities until the art pack has them.
    private func updateProp() {
        let want = body.mode == .grounded ? Self.props[brain.current] : nil
        guard want != propEmoji else { return }
        prop?.removeFromParent()
        prop = nil
        propEmoji = want
        guard let want else { return }
        let p = Effects.makeProp(want)
        let side: CGFloat = body.facingRight ? 1 : -1
        let w = backend.size.width, h = backend.size.height
        switch brain.current {
        case .music: p.position = CGPoint(x: side * w * 0.35, y: h * 0.7)
        case .watchTV: p.position = CGPoint(x: side * (w / 2 + 26), y: 0)
        case .playBallHome:
            p.position = CGPoint(x: side * (w / 2 + 6), y: 0)
            p.run(.repeatForever(.sequence([.moveBy(x: 0, y: 16, duration: 0.25), .moveBy(x: 0, y: -16, duration: 0.25)])))
        default: p.position = CGPoint(x: side * (w / 2 + 2), y: 2)
        }
        backend.node.addChild(p)
        prop = p
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        needs.tick()
        updateRest(dt: dt, now: now)

        home.observe(body.position)
        let canHop = !world.reachableSegments(from: body.position, maxJumpUp: body.config.maxJumpUp,
                                              maxJumpAcross: body.config.maxJumpAcross).isEmpty
        let ctx = BrainContext(needs: needs.state, lowThreshold: needs.config.lowThreshold, canHop: canHop,
                               atHome: home.isHome(body.position), secondsAwayFromHome: home.secondsAway)
        if let next = brain.update(dt: dt, ctx) { beginBehavior(next) }

        let cursor = NSEvent.mouseLocation
        updateHover(dt: dt, cursor: cursor)
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
        if brain.current.countsAsSleep && now - lastZzz > 2 {
            lastZzz = now
            Effects.floatEmoji("💤", on: backend.node, height: backend.size.height * 0.8)
        }
        if body.mode == .held && now - lastSweat > 0.6 {
            lastSweat = now
            Effects.floatEmoji("💦", on: backend.node, height: backend.size.height * 0.9)
        }
        updateProp()
        debug.update(world: world, hitRect: hitRect, behavior: brain.current, overlays: overlays)
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor)))
        setRate(body.isMoving || body.mode == .held || animOverride != nil ? 30 : 10)
    }

    private func updateAnimation(_ now: CFTimeInterval) {
        if let o = animOverride, o.until <= now { animOverride = nil }
        let state = animOverride?.state
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving, isRunning: body.isRunning)
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
            brain.interrupt(with: .goHome, duration: 30)
            beginBehavior(.goHome)
        } else if pressPoint != nil {
            pet()
        }
    }

    func rightMouseDown(_ event: NSEvent, in view: NSView) {
        onRightClick?(event, view)
    }

    func pet() {
        if brain.current.countsAsSleep {
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
