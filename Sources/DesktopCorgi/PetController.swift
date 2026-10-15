#if canImport(AppKit)
import AppKit
import CorgiCore
import SpriteKit

/// Temporary debug trace for the Play Ball investigation.
func corgiDebug(_ msg: String) {
    let line = "\(Date()) \(msg)\n"
    let url = URL(fileURLWithPath: "/tmp/corgi-debug.log")
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? Data(line.utf8).write(to: url)
    }
}

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
    private(set) var chaseMe = false
    let boredom = BoredomTimer(clock: SystemClock())
    private var ball: Ball?
    private var ballNode: SKShapeNode?
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
    private var restPollElapsed: TimeInterval = 0
    private var lastClickPet: CFTimeInterval = 0
    let sounds = SoundPlayer()
    private var moodBubbles = MoodBubbles()
    private static let props: [Behavior: String] = [
        .read: "📖", .readSleep: "📖", .music: "🎧", .watchTV: "📺", .playBallHome: "⚽️",
    ]

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        overlays = OverlayManager(corgiNode: backend.node)
        world = World(provider: CGWindowListProvider(), screens: NSScreen.screens.map(\.visibleFrame))
        let frames = NSScreen.screens.map(\.visibleFrame)
        let vf = HomeTracker.cornerScreenIndex(frames).map { frames[$0] } ?? .zero
        body = Body(position: CGPoint(x: vf.maxX - 80, y: vf.maxY - 100))
        overlays.input = self
        updateHome()
        executor.onBallCaught = { [weak self] in self?.ballCaught() }
    }

    /// Home is on the primary screen (the one with the menu bar), index 0 in `world.screens`.
    private func updateHome() {
        home.setScreens(world.screens, mainIndex: HomeTracker.cornerScreenIndex(world.screens) ?? 0)
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
            Effects.speech(line, on: backend.node, height: backend.bubbleHeight, delay: Double(i) * 2.6)
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
        let update = world.refresh()
        if body.mode == .clinging {
            if body.followCling(world) == .startedFalling { fell() }
            return
        }
        if body.apply(update) == .startedFalling { fell() }
    }

    func screensChanged() {
        world.setScreens(NSScreen.screens.map(\.visibleFrame))
        overlays.rebuild()
        overlays.setPaused(paused)
        if timerFPS > 0 { overlays.setFPS(timerFPS) }
        body.clamp(to: world.screens)
        updateHome()
        ball?.setScreens(world.screens)
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
        Effects.floatDoodle("exclamation", fallback: "❗", on: backend.node, height: backend.size.height)
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        if body.mode == .clinging && b != .cling && b != .dangle {
            body.letGo()
            animOverride = (.letGo, CACurrentMediaTime() + 0.5)
        }
        corgiDebug("begin \(b.rawValue) mode=\(body.mode) pos=\(body.position) ball=\(ball != nil)")
        if b != .ballChase { endBall() }
        if chaseMe && b != .chaseMe && b != .dangle { chaseMe = false }
        if b.countsAsSleep && !needs.state.isAsleep { sounds.play(.purr) }
        if needs.state.isAsleep != b.countsAsSleep { needs.setAsleep(b.countsAsSleep) }
        if b == .eat { sounds.play(.bottle) }
        executor.speedScale = needs.isLow(.happiness) ? 0.6 : 1
        executor.begin(b, body: body, world: world, cursor: NSEvent.mouseLocation)
        if b == .ballChase { spawnBall() }
    }

    /// The executor says the current behavior is done.
    func stepFinished() {
        corgiDebug("stepFinished \(brain.current.rawValue) carrying=\(executor.carryingBall)")
        if brain.current == .ballChase && executor.carryingBall {
            brain.interrupt(with: .playBallHome, duration: Double.random(in: 8...15))
            beginBehavior(.playBallHome)
            return
        }
        brain.finishCurrent()
    }

    func feed() {
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .eat, duration: 4)
        beginBehavior(.eat)
        needs.feed()
        Effects.floatDoodle("menu:feed", fallback: "🍖", on: backend.node, height: backend.size.height)
    }

    func bath() {
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .bath, duration: 4)
        beginBehavior(.bath)
        needs.bath()
        Effects.floatDoodle("sparkles", fallback: "🫧", on: backend.node, height: backend.size.height, count: 5)
    }

    func nap() {
        boredom.noteInteraction()
        brain.interrupt(with: .sleep, duration: 120)
        beginBehavior(.sleep)
    }

    /// Throws a ball that flies around the screen. The corgi chases it, carries it home, and plays.
    func playBall() {
        corgiDebug("playBall current=\(brain.current.rawValue)")
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .ballChase, duration: 30)
        beginBehavior(.ballChase)
    }

    /// Menu toggle. On: roam freely and dodge the cursor. Off: fall to the floor and go home.
    func setChaseMe(_ on: Bool) {
        guard on != chaseMe else { return }
        boredom.noteInteraction()
        if on {
            wake()
            brain.interrupt(with: .chaseMe, duration: .infinity)
            beginBehavior(.chaseMe)
            chaseMe = true
        } else {
            chaseMe = false
            brain.interrupt(with: .goHome, duration: 30)
            beginBehavior(.goHome)
        }
    }

    private func wake() {
        if brain.current.countsAsSleep { brain.finishCurrent() }
        if needs.state.isAsleep { needs.setAsleep(false) }
    }

    private func spawnBall() {
        endBall()
        let b = Ball(start: CGPoint(x: body.position.x, y: body.position.y + 60), screens: world.screens)
        ball = b
        let node = Effects.makeBall()
        ballNode = node
        overlays.place(node, global: b.position)
        corgiDebug("spawnBall at=\(b.position) screens=\(world.screens) scene=\(node.scene != nil) bodyMode=\(body.mode)")
        executor.ballPosition = b.position
        boredom.noteInteraction()
    }

    /// The executor reached the ball: +25 happiness and the ball moves to the corgi's mouth.
    private func ballCaught() {
        corgiDebug("ballCaught")
        needs.play()
        boredom.noteInteraction()
        sounds.play(.tink)
        Effects.floatDoodle("heart", fallback: "❤️", on: backend.node, height: backend.size.height, count: 3)
        ball = nil
        executor.ballPosition = nil
        if let node = ballNode {
            node.removeFromParent()
            node.position = carryPoint
            node.zPosition = 20
            backend.node.addChild(node)
        }
    }

    private var carryPoint: CGPoint {
        let m = backend.mouthPoint
        return CGPoint(x: body.facingRight ? m.x : -m.x, y: m.y)
    }

    private func stepBall(dt: TimeInterval) {
        guard let b = ball else { return }
        b.step(dt: dt)
        if b.popped {
            corgiDebug("ball popped at=\(b.position) corgi=\(body.position)")
            if let node = ballNode, let scene = node.parent {
                let pop: SKNode = Doodles.texture("starburst").map { SKSpriteNode(texture: $0, size: CGSize(width: 30, height: 30)) }
                    ?? { let l = SKLabelNode(text: "💥"); l.fontSize = 22; return l }()
                pop.position = node.position
                scene.addChild(pop)
                pop.run(.sequence([.fadeOut(withDuration: 0.6), .removeFromParent()]))
            }
            endBall()
            return
        }
        executor.ballPosition = b.position
        if let node = ballNode { overlays.place(node, global: b.position) }
    }

    private func endBall() {
        if ball != nil || ballNode != nil { corgiDebug("endBall current=\(brain.current.rawValue)") }
        ballNode?.removeFromParent()
        ballNode = nil
        ball = nil
        executor.ballPosition = nil
    }

    /// Seconds since any keyboard or mouse event. Needs no permission.
    private var userIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// A nap or a doze over the book is already rest; idle sleep must not yawn over it.
    private var restBusy: Bool {
        dragging || chaseMe || body.mode == .held || body.mode == .roaming || body.mode == .clinging
            || brain.current == .ballChase
            || brain.current == .sleep || brain.current == .readSleep
    }

    /// Polls idle time and full screen twice a second, not every frame.
    private func updateRest(dt: TimeInterval, now: CFTimeInterval) {
        restPollElapsed += dt
        guard restPollElapsed >= 0.5 else { return }
        let dt = restPollElapsed
        restPollElapsed = 0
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
            // Still resting but something (a fall) took it out of idle sleep: settle back down.
            if rest.phase == .asleep && brain.current != .idleSleep && brain.current != .fall
                && body.mode == .grounded && !restBusy {
                brain.interrupt(with: .idleSleep, duration: .infinity)
                beginBehavior(.idleSleep)
            }
        }
    }

    private func updateHover(dt: TimeInterval, cursor: CGPoint) {
        let blocked = dragging || pressPoint != nil || (body.mode != .grounded && body.mode != .clinging)
            || brain.current.countsAsSleep || brain.current == .yawn
            || CACurrentMediaTime() - lastClickPet < hover.repeatEvery
        if hover.update(dt: dt, hovering: hitRect.contains(cursor), blocked: blocked) { hoverPet() }
    }

    private func hoverPet() {
        boredom.noteInteraction()
        if needs.pet() {
            sounds.play(.pop)
            Effects.floatDoodle("heart", fallback: "❤️", on: backend.node, height: backend.size.height, count: 2)
            animOverride = (.happy, CACurrentMediaTime() + 0.8)
        }
    }

    /// Emoji props for idle activities until the art pack has them.
    private func updateProp() {
        let want = body.mode == .grounded && !backend.drawsProps ? Self.props[brain.current] : nil
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
                               atHome: home.isHome(body.position), secondsAwayFromHome: home.secondsAway,
                               bored: boredom.isBored(needs.state))
        if let next = brain.update(dt: dt, ctx) { beginBehavior(next) }

        let cursor = NSEvent.mouseLocation
        updateHover(dt: dt, cursor: cursor)
        backend.setHovering(body.mode == .grounded && hitRect.contains(cursor))
        backend.setHappy(needs.state.happiness > 70)
        updateMoodBubble(dt: dt)
        stepBall(dt: dt)
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
        // Cling sprites are drawn for their side already, so they are never mirrored.
        backend.setFacing(right: body.mode == .clinging ? true : body.facingRight)
        updateAnimation(now)
        if brain.current.countsAsSleep && now - lastZzz > 2 {
            lastZzz = now
            Effects.floatDoodle("zzz", fallback: "💤", on: backend.node, height: backend.size.height * 0.8)
        }
        if body.mode == .held && now - lastSweat > 0.6 {
            lastSweat = now
            Effects.floatDoodle("sweat-drops", fallback: "💦", on: backend.node, height: backend.size.height * 0.9)
        }
        if executor.carryingBall, let n = ballNode, n.parent === backend.node {
            n.position = carryPoint
            n.isHidden = backend.drawsProps   // the holdBall sprite already has the ball in its mouth
        }
        updateProp()
        debug.update(world: world, hitRect: hitRect, behavior: brain.current, overlays: overlays)
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor)))
        setRate(body.isMoving || body.mode == .held || animOverride != nil || ball != nil ? 30 : 15)
    }

    /// A thought bubble for the lowest low need, about once a minute.
    private func updateMoodBubble(dt: TimeInterval) {
        let blocked = needs.state.isAsleep || brain.current.countsAsSleep
            || body.mode == .held || body.mode == .roaming
        guard let need = moodBubbles.update(dt: dt, needs: needs.state, blocked: blocked) else { return }
        let icon: String
        switch need {
        case .hunger: icon = "menu:feed"
        case .happiness: icon = "heart"
        case .energy: icon = "moon"
        case .cleanliness: icon = "sparkles"
        }
        Effects.thought(icon: icon, fallback: MoodBubbles.bubbleText(for: need), on: backend.node,
                        height: backend.bubbleHeight)
    }

    /// The name tag and the hat, from the saved profile.
    func applyProfile(_ profile: PetProfile) {
        backend.setName(profile.name)
        backend.setNameTagVisible(profile.showNameTag)
        backend.setHat(profile.hat)
        sounds.enabled = profile.soundsOn
    }

    private func updateAnimation(_ now: CFTimeInterval) {
        if let o = animOverride, o.until <= now { animOverride = nil }
        let state = animOverride?.state
            ?? body.cling?.animState
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving,
                         isRunning: body.isRunning, carrying: executor.carryingBall)
        if state != currentAnim {
            currentAnim = state
            backend.play(state)
        }
    }
}

extension PetController: SceneInputHandler {
    func mouseDown(at global: CGPoint) {
        // The panel takes clicks while the cursor was over the corgi last tick; a roaming corgi may have moved off.
        guard hitRect.contains(global) else {
            pressPoint = nil
            return
        }
        pressPoint = global
        dragging = false
    }

    func mouseDragged(to global: CGPoint) {
        guard let start = pressPoint else { return }
        if !dragging && hypot(global.x - start.x, global.y - start.y) > 4 {
            dragging = true
            boredom.noteInteraction()
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
            if chaseMe {
                brain.interrupt(with: .chaseMe, duration: .infinity)
                beginBehavior(.chaseMe)
            } else if let spot = ClingFinder.find(global, windows: world.windows),
                      let contact = ClingFinder.contact(spot, windows: world.windows) {
                // Dropped near a window edge: hold on to it until bored.
                body.startClinging(spot, at: contact)
                brain.interrupt(with: .cling, duration: Double.random(in: 180...360))
                beginBehavior(.cling)
            } else {
                // Stay where dropped. Home still pulls it back slowly via the brain's goHome weight.
                brain.interrupt(with: .fall, duration: 5)
                beginBehavior(.fall)
            }
        } else if pressPoint != nil {
            pet()
        }
    }

    func rightMouseDown(_ event: NSEvent, in view: NSView) {
        onRightClick?(event, view)
    }

    func pet() {
        boredom.noteInteraction()
        lastClickPet = CACurrentMediaTime()
        if chaseMe {
            if needs.catchPet() {
                sounds.play(.pop)
                Effects.floatDoodle("heart", fallback: "❤️", on: backend.node, height: backend.size.height, count: 4)
                animOverride = (.happy, CACurrentMediaTime() + 0.8)
            }
            return
        }
        if brain.current.countsAsSleep {
            brain.finishCurrent()
            needs.setAsleep(false)
        }
        if needs.pet() {
            sounds.play(.pop)
            Effects.floatDoodle("heart", fallback: "❤️", on: backend.node, height: backend.size.height, count: 3)
            animOverride = (.wiggle, CACurrentMediaTime() + 0.8)
        }
    }
}
#endif
