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

    private let playback: AnimationPlayback
    private var saidRefreshed = false
    /// After you drop it somewhere it stays around that spot (x) until `stayUntil`.
    static let stayPutSeconds: CFTimeInterval = 10 * 60
    private var stayUntil: CFTimeInterval = 0
    private var stayX: CGFloat = 0
    /// Hiding behind a screen edge after being dropped next to it.
    private var peek: EdgePeekSession?
    /// The brick wall it hides behind (when the pack has one).
    private let edgeWall = EdgeWall()

    /// Each display's current Space, to tell which way a switch went (`Spaces`).
    private var spaces: [String: Int] = [:]
    /// The display it's running in on after a Space switch, while it's still past the edge.
    private var enteringScreen: Int?

    /// The current click started on a bubble, so its release isn't a pet.
    private var bubbleTapped = false

    /// When the eating or drinking loop first showed, and when that meal ends.
    private var mealStart: CFTimeInterval?
    private var mealEnd: CFTimeInterval = 0
    /// The behavior that started the current transition.
    private var transitionBehavior: Behavior?
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
    /// When it last ran hard, so it asks for water or food sooner right after.
    private var lastHardExercise: CFTimeInterval = -.infinity
    private var lastSweat: CFTimeInterval = 0
    let home = HomeTracker(clock: SystemClock())
    let rest = RestMonitor()
    let hover = HoverPet()
    private var restPollElapsed: TimeInterval = 0
    private var lastClickPet: CFTimeInterval = 0
    let sounds = SoundPlayer()
    private var petSound: SoundPlayer.Effect = .petCorgi
    private var snoreTick = false
    private var stepElapsed: TimeInterval = 0
    private var wasGrounded = true
    private var moodBubbles = MoodBubbles()
    private var careAsker = CareAsker()
    private var speech: SpeechLibrary? = Bundle.main.resourceURL
        .flatMap { try? Data(contentsOf: $0.appendingPathComponent("Bubbles/messages.json")) }
        .flatMap { try? SpeechLibrary(data: $0) }
    private var character: Character = .corgi
    private var careLine: SpeechLibrary.Line?
    private var sadVariant = 0
    /// Spontaneous lines (mood, company, happy) stay at least a minute apart.
    private var lastAutoLine: CFTimeInterval = -100
    private var nextCompany = CACurrentMediaTime() + Double.random(in: 20 * 60...40 * 60)
    /// What it came over to ask for, while `brain.current == .askCare`.
    private(set) var askingFor: Need?
    var askForCare = true
    private var careCheckElapsed: TimeInterval = 0
    private var lastCareBubble: CFTimeInterval = 0

    init(needs: NeedsEngine, backend: AnimationBackend) {
        self.needs = needs
        self.backend = backend
        playback = AnimationPlayback(backend: backend, graph: TransitionGraph(postures: backend.postures, bridges: backend.bridgeNames,
                                                                              direct: backend.directPairs))
        overlays = OverlayManager(corgiNode: backend.node)
        playback.trace = { TransitionLog.append($0) }
        let frames = NSScreen.screens.map(\.visibleFrame)
        world = World(provider: CGWindowListProvider(), screens: frames, bodyBounds: backend.movementBounds)
        world.setScreens(frames, fullFrames: NSScreen.screens.map(\.frame))
        displayScales = Self.physicalScales()
        let vf = HomeTracker.cornerScreenIndex(frames).map { frames[$0] } ?? .zero
        let initial = CGPoint(x: vf.maxX - 80, y: vf.maxY - 100)
        body = Body(position: nearestPoint(to: initial, in: world.movementScreens))
        overlays.input = self
        updateHome()
        executor.onBallCaught = { [weak self] in self?.ballCaught() }
    }

    /// Home is on the primary screen (the one with the menu bar), index 0 in `world.screens`.
    private func updateHome() {
        home.setScreens(world.screens, mainIndex: HomeTracker.cornerScreenIndex(world.screens) ?? 0,
                        bodyBounds: world.bodyBounds)
        executor.home = home.spot
    }

    var hitRect: CGRect {
        let b = backend.spriteBounds, s = drawScale
        return CGRect(x: b.minX * s, y: b.minY * s, width: b.width * s, height: b.height * s)
            .offsetBy(dx: body.position.x, dy: body.position.y)
    }

    /// Point-to-millimetre ratio of each display relative to the built-in one, so the pet is drawn smaller on
    /// a display with big points (a 27" 1440p monitor) and looks the same physical size everywhere.
    private var displayScales: [CGFloat] = []
    /// The scale the pet is drawn at right now; eases toward the display it's on so crossing a seam doesn't pop.
    private var drawScale: CGFloat = 1

    private static func physicalScales() -> [CGFloat] {
        let screens = NSScreen.screens
        let mmPerPoint: [CGFloat?] = screens.map { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let mm = CGDisplayScreenSize(n.uint32Value).width
            return mm > 0 && s.frame.width > 0 ? mm / s.frame.width : nil
        }
        let builtIn = screens.indices.first { i in
            (screens[i].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }
        guard let ref = mmPerPoint[builtIn ?? 0] ?? mmPerPoint.compactMap({ $0 }).min() else {
            return screens.map { _ in 1 }
        }
        return mmPerPoint.map { $0.map { min(1.25, max(0.6, ref / $0)) } ?? 1 }
    }

    /// Logs the details whenever the pet is drawn far bigger or smaller than its normal size, so a size glitch
    /// can be traced from ~/Library/Logs/DesktopPet/transitions.log. At most once a second.
    private var lastSizeLog: CFTimeInterval = 0
    private func checkSpriteSize() {
        let sprite = backend.spriteNode
        let h = abs(sprite.size.height) * backend.node.yScale
        let normal = backend.size.height
        guard normal > 0, h > normal * 1.6 || h < normal * 0.4 else { return }
        let now = CACurrentMediaTime()
        guard now - lastSizeLog > 1 else { return }
        lastSizeLog = now
        let t = sprite.texture?.size() ?? .zero
        TransitionLog.append("SIZE \(Int(h))pt vs \(Int(normal)) state=\(playback.currentState?.rawValue ?? "nil") "
            + "target=\(playback.transitionTarget?.rawValue ?? "-") behavior=\(brain.current.rawValue) mode=\(body.mode) "
            + "texture=\(Int(t.width))x\(Int(t.height)) size=\(Int(sprite.size.width))x\(Int(sprite.size.height)) "
            + "xs=\(sprite.xScale) ys=\(sprite.yScale) node=\(backend.node.xScale) at \(Int(body.position.x)),\(Int(body.position.y)) "
            + "lastSet=[\(backend.lastSetSize)] actions=\(sprite.hasActions())")
    }

    private func updateDrawScale(dt: TimeInterval) {
        let target = (world.display(at: body.position) ?? enteringScreen).flatMap { displayScales.indices.contains($0) ? displayScales[$0] : nil } ?? 1
        drawScale += (target - drawScale) * min(1, CGFloat(dt) * 5)
        if abs(drawScale - target) < 0.002 { drawScale = target }
        if backend.node.xScale != drawScale { backend.node.setScale(drawScale) }
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
        spaces = Spaces.current()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.spaceChanged() }
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
        sounds.play(.happy)
        let lines = Greeting.lines(awaySeconds: awaySeconds)
        brain.interrupt(with: .greet, duration: lines.count > 1 ? 9 : 4.5)
        beginBehavior(.greet)
        for (i, line) in lines.enumerated() {
            let shown = say(SpeechLibrary.Line(text: line, bubble: .speech, icon: i == 0 ? "hearts" : "heart"),
                            delay: Double(i) * 4.6)
            if !shown { Effects.speech(line, on: backend.node, height: backend.bubbleHeight, delay: Double(i) * 2.6) }
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

    /// The Dock can change the visible area without changing a screen's physical frame.
    private func refreshScreenBounds() {
        let frames = NSScreen.screens.map(\.visibleFrame)
        guard frames != world.screens else { return }
        if peek != nil { endPeek(reason: "screens changed") }
        world.setScreens(frames, fullFrames: NSScreen.screens.map(\.frame))
        displayScales = Self.physicalScales()
        updateHome()
        ball?.setArea(ballArea)
    }

    private func clampBody() {
        // A pet on a floor, or falling onto one, is where it should be; only rescue it when it's truly lost.
        if body.mode == .grounded, world.segment(under: body.position) != nil { return }
        // Hiding behind a screen edge is meant to be past the normal area; `updatePeek` checks the spot.
        if body.mode == .peeking || body.mode == .entering { return }
        if body.mode == .airborne, world.hasFloor(below: body.position) { return }
        let areas = body.cling.map { placementRects(world.screens, bounds: backend.bounds(for: $0.animState)) }
            ?? world.movementScreens
        if body.clamp(to: areas) == .startedFalling {
            body.clamp(to: world.movementScreens)
            fell()
        }
    }

    func refreshWorld() {
        refreshScreenBounds()
        let update = world.refresh()
        if body.mode == .clinging {
            if body.followCling(world) == .startedFalling { fell() }
        } else if body.apply(update) == .startedFalling {
            fell()
        }
        clampBody()
    }

    func screensChanged() {
        if overlays.overlays.map(\.frame) != NSScreen.screens.map(\.frame) {
            overlays.rebuild()
            overlays.setPaused(paused)
            if timerFPS > 0 { overlays.setFPS(timerFPS) }
        }
        refreshScreenBounds()
        clampBody()
        overlays.place(globalFeet: body.position)
        overlays.mirror(backend.spriteNode, globalFeet: body.position, scale: drawScale)
    }

    /// Switched to another Space (a three-finger swipe, Ctrl-arrow, Mission Control). The overlay is on every Space,
    /// so instead of just being there it runs in from the side the old Space slid off to.
    private func spaceChanged() {
        let before = spaces
        spaces = Spaces.current()
        defer { refreshWorld() }
        guard let i = world.display(at: body.position), NSScreen.screens.indices.contains(i),
              let floor = world.ground(of: i) else { return }
        let key = Spaces.key(of: NSScreen.screens[i], in: spaces)
        let step = key.flatMap { k in before[k].flatMap { b in spaces[k].map { $0 - b } } }
        let busy: Set<Behavior> = [.eat, .drink, .bath, .greet, .dangle, .fall, .cling, .peek, .chaseMe, .askCare, .ballChase]
        guard !paused, !dragging, pressPoint == nil, peek == nil, ball == nil, body.mode == .grounded,
              !brain.current.countsAsSleep, !busy.contains(brain.current) else { return }
        let b = backend.bounds(for: .run)
        guard let plan = SpaceArrival.plan(step: step, screen: world.screens[i], floor: floor, feetX: body.position.x,
                                           reach: max(abs(b.minX), abs(b.maxX)) * targetScale(on: i) + 8,
                                           depth: .random(in: 0.2...0.45)) else { return }
        TransitionLog.append("space switch (step \(step.map(String.init) ?? "?")): run in from the "
            + (plan.fromLeft ? "left" : "right") + " on screen \(i) to x=\(Int(plan.stopX))")
        brain.interrupt(with: .arrive, duration: .infinity)
        beginBehavior(.arrive)
        executor.arriveX = plan.stopX
        enteringScreen = i
        body.startEntering(onto: floor, from: plan.startX)
    }

    /// A one-off line that isn't about its needs, like a new version being out. Quiet while hiding at an edge.
    func announce(_ text: String) {
        _ = say(SpeechLibrary.Line(text: text, bubble: .speech, icon: "sparkles"))
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
        TransitionLog.append("fell at \(Int(body.position.x)),\(Int(body.position.y)) during \(brain.current.rawValue)")
        Effects.floatDoodle("exclamation", fallback: "❗", on: backend.node, height: backend.size.height)
        brain.interrupt(with: .fall, duration: 5)
        beginBehavior(.fall)
    }

    func beginBehavior(_ b: Behavior) {
        playback.cancelReaction()
        if b != .askCare, askingFor != nil {
            // Ignored: a little tear, then back to what it was doing. It asks again later.
            askingFor = nil
            Effects.floatDoodle("teardrop", fallback: "💧", on: backend.node, height: backend.size.height)
        }
        if b != .peek && peek != nil { endPeek(reason: "now \(b.rawValue)") }
        if body.mode == .clinging && b != .cling && b != .dangle {
            body.letGo()
            sounds.play(.letGo)
            playback.requestReaction(.letGo, mode: body.mode)
        }
        if b != .ballChase { endBall() }
        if chaseMe && b != .chaseMe && b != .dangle { chaseMe = false }
        if b.countsAsSleep && !needs.state.isAsleep { sounds.play(.snore) }
        if b == .yawn { sounds.play(.yawn) }
        if needs.state.isAsleep != b.countsAsSleep { needs.setAsleep(b.countsAsSleep) }
        if b == .eat { sounds.play(.eat) }
        if b == .drink {
            sounds.play(.drink)
            saidRefreshed = false
        }
        if b == .bath { sounds.play(.bath) }
        if b == .sit && brain.catchingBreath {
            Effects.floatDoodle("sweat-drops", fallback: "💦", on: backend.node, height: backend.size.height * 0.9)
        }
        executor.speedScale = needs.isLow(.happiness) ? 0.6 : 1
        executor.begin(b, body: body, world: world, cursor: NSEvent.mouseLocation)
        if b == .ballChase { spawnBall() }
    }

    /// The executor says the current behavior is done.
    func stepFinished() {
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
        brain.interrupt(with: .eat, duration: Self.eatSeconds)
        beginBehavior(.eat)
        needs.feed()
        Effects.floatDoodle("menu:feed", fallback: "🍖", on: backend.node, height: backend.size.height)
    }

    static let eatSeconds = 4.0
    static let drinkSeconds = 4.0
    static let refreshedSeconds = 2.0

    /// How far through the meal it is, counted from when the eating or drinking loop first shows
    /// (getting down to the bowl doesn't use up the full bowl).
    private func mealProgress(for base: AnimState) -> Double {
        let now = CACurrentMediaTime()
        if mealStart == nil {
            guard playback.transitionTarget == nil, playback.currentState?.base == base else { return 0 }
            mealStart = now
            mealEnd = now + max(0.5, base == .drink ? brain.remaining - Self.refreshedSeconds : brain.remaining)
        }
        guard let start = mealStart else { return 0 }
        return min(1, (now - start) / (mealEnd - start))
    }

    /// Full, half or empty bowl as the meal goes on (0 at the start, 1 when done).
    private static func bowl(_ base: AnimState, progress: Double) -> AnimState {
        let half: AnimState = base == .eat ? .eatHalf : .drinkHalf
        let empty: AnimState = base == .eat ? .eatEmpty : .drinkEmpty
        return progress < 0.35 ? base : progress < 0.7 ? half : empty
    }

    /// A few laps from the water bowl, then a happy "ahh".
    func drink() {
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .drink, duration: Self.drinkSeconds + Self.refreshedSeconds)
        beginBehavior(.drink)
        needs.drink()
        // The drinking frames are subtle at desktop size, so keep the laps audible the whole time.
        for k in 1...2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3 * Double(k)) { [weak self] in
                guard let self, self.brain.current == .drink else { return }
                self.sounds.play(.drink)
            }
        }
        Effects.floatDoodle("water-droplet", fallback: "💧", on: backend.node, height: backend.size.height, count: 3)
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
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .ballChase, duration: 30)
        beginBehavior(.ballChase)
    }

    /// Menu toggle. On: fly after the cursor and wait beside it. Off: fall to the floor and go home.
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

    private var ballArea: [CGRect] {
        Ball.area(for: world.screens, reachableFrom: world.roamingScreens(headroom: body.config.roamHeadroom))
    }

    private func spawnBall() {
        endBall()
        let b = Ball(start: CGPoint(x: body.position.x, y: body.position.y + 60), screens: world.screens)
        b.setArea(ballArea)
        ball = b
        sounds.play(.ballBounce)
        let node = Effects.makeBall()
        ballNode = node
        overlays.place(node, global: b.position)
        executor.ballPosition = b.position
        boredom.noteInteraction()
    }

    /// The executor reached the ball: +25 happiness and the ball moves to the corgi's mouth.
    private func ballCaught() {
        needs.play()
        boredom.noteInteraction()
        sounds.play(.ballCatch)
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
            sounds.play(.ballPop)
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
        dragging || chaseMe || body.mode == .held || body.mode == .roaming || body.mode == .clinging || peek != nil
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
                playback.requestReaction(.wiggle, mode: body.mode)
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
        let blocked = dragging || pressPoint != nil || (body.mode != .grounded && body.mode != .clinging && body.mode != .peeking)
            || brain.current.countsAsSleep || brain.current == .yawn
            || CACurrentMediaTime() - lastClickPet < hover.repeatEvery
        if hover.update(dt: dt, hovering: hitRect.contains(cursor), blocked: blocked) { hoverPet() }
    }

    private func hoverPet() {
        // Hiding behind the wall: no hearts, wiggles or sounds.
        if peek != nil { return }
        boredom.noteInteraction()
        if needs.pet() {
            sounds.play(petSound)
            Effects.floatDoodle("heart", fallback: "❤️", on: backend.node, height: backend.size.height, count: 2)
            playback.requestReaction(.happy, mode: body.mode)
        }
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        refreshScreenBounds()
        clampBody()
        playback.advance(dt: dt, mode: body.mode)
        needs.tick()
        updateRest(dt: dt, now: now)

        home.observe(body.position)
        let canHop = !world.reachableSegments(from: body.position, maxJumpUp: body.config.maxJumpUp,
                                              maxJumpAcross: body.config.maxJumpAcross).isEmpty
        let ctx = BrainContext(needs: needs.state, lowThreshold: needs.config.lowThreshold, canHop: canHop,
                               atHome: home.isHome(body.position), secondsAwayFromHome: home.secondsAway,
                               bored: boredom.isBored(needs.state),
                               secondsSinceInteraction: boredom.secondsSinceInteraction,
                               stayPut: now < stayUntil, asksForCare: askForCare)
        // Do not call update with dt=0: the brain can still change behaviors at zero elapsed time.
        executor.leash = now < stayUntil ? (center: stayX, radius: 300) : nil
        if !playback.holdsGroundedMotion(in: body.mode), let next = brain.update(dt: dt, ctx) {
            beginBehavior(next)
        }

        let cursor = NSEvent.mouseLocation
        updateHover(dt: dt, cursor: cursor)
        updateMoodBubble(dt: dt)
        updateCareRequest(dt: dt, now: now)
        updateCompany(now: now)
        stepBall(dt: dt)
        if playback.holdsGroundedMotion(in: body.mode) {
            body.stop()
            body.hover()
        } else if executor.step(brain.current, body: body, world: world, cursor: cursor) {
            stepFinished()
        }
        // Even a planted reaction must notice a vanished floor and start falling immediately.
        if let event = body.step(dt: dt, world: world) {
            if executor.handle(event, behavior: brain.current, body: body) { stepFinished() }
            if event == .landed {
                // Landing after being dropped: that's the spot to stay around.
                if now < stayUntil && stayUntil - now > Self.stayPutSeconds - 6 { stayX = body.position.x }
                sounds.play(.land)
                playback.requestReaction(.land, mode: body.mode)
                if brain.current == .fall { brain.finishCurrent() }
            }
            if event == .startedFalling { fell() }
        }
        if enteringScreen != nil && body.mode != .entering {
            enteringScreen = nil
            // Something else started while it ran in (fed, say): it stops once it's on the floor.
            if brain.current != .arrive { body.stop() }
        }
        updatePeek(dt: dt)
        clampBody()
        updateMovementSounds(dt: dt)
        updateDrawScale(dt: dt)
        checkSpriteSize()
        let effort: Exertion = body.isRunning || (body.isMoving && brain.current.exertion == .hard) ? .hard
            : body.isMoving ? .light : .rest
        needs.exert(effort, seconds: dt)
        if effort == .hard { lastHardExercise = now }

        if let i = enteringScreen {
            // Still past the edge: drawn only on its own display, which hides the part not in yet.
            overlays.place(globalFeet: body.position, screen: i)
            overlays.hideMirrors()
        } else {
            overlays.place(globalFeet: body.position)
            overlays.mirror(backend.spriteNode, globalFeet: body.position, scale: drawScale)
        }
        // Cling sprites are drawn for their side already, so they are never mirrored.
        backend.setFacing(right: body.mode == .clinging ? true : body.facingRight)
        updateAnimation()
        if brain.current.countsAsSleep && now - lastZzz > 2 {
            lastZzz = now
            snoreTick.toggle()
            if snoreTick { sounds.play(.snore) }   // every other Zzz, about every 4s
            Effects.floatDoodle("zzz", fallback: "💤", on: backend.node, height: backend.size.height * 0.8)
        }
        if body.mode == .held && now - lastSweat > 0.6 {
            lastSweat = now
            Effects.floatDoodle("sweat-drops", fallback: "💦", on: backend.node, height: backend.size.height * 0.9)
        }
        if executor.carryingBall, let n = ballNode, n.parent === backend.node {
            n.position = carryPoint
            n.isHidden = true   // the holdBall sprite already has the ball in its mouth
        }
        debug.update(world: world, hitRect: hitRect, behavior: brain.current, overlays: overlays)
        let overBubble = visibleBubble()?.rect.contains(cursor) ?? false
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor) || overBubble))
        setRate(body.isMoving || body.mode == .held || playback.reactionState != nil || playback.transitionTarget != nil || ball != nil ? 30 : 15)
    }

    /// A thought bubble for the lowest low need, about once a minute.
    private func updateMoodBubble(dt: TimeInterval) {
        // "I want something" bubbles and lines are asking for care too.
        let blocked = !askForCare || peek != nil || needs.state.isAsleep || brain.current.countsAsSleep
            || body.mode == .held || body.mode == .roaming
        guard let need = moodBubbles.update(dt: dt, needs: needs.state, blocked: blocked) else { return }
        sadVariant += 1
        if say(mood: SpeechLibrary.category(for: need, variant: sadVariant)) {
            lastAutoLine = CACurrentMediaTime()
            return
        }
        Effects.thought(icon: Self.icon(for: need), fallback: MoodBubbles.bubbleText(for: need), on: backend.node,
                        height: backend.bubbleHeight)
        tagNewestBubble(need: need)
    }

    private static func icon(for need: Need) -> String {
        switch need {
        case .hunger: return "menu:feed"
        case .happiness: return "heart"
        case .energy: return "moon"
        case .cleanliness: return "sparkles"
        case .thirst: return "water-droplet"
        }
    }

    /// Now and then a low need sends it to your cursor to ask for help; click it to give it what it wants.
    private func updateCareRequest(dt: TimeInterval, now: CFTimeInterval) {
        if brain.current == .askCare, let need = askingFor {
            if !body.isMoving && now - lastCareBubble > 3.2 {
                if lastCareBubble == 0 {
                    sounds.play(petSound)
                    sadVariant += 1
                    careLine = speech?.line(for: SpeechLibrary.category(for: need, variant: sadVariant), pet: character)
                }
                lastCareBubble = now
                if !(careLine.map { say($0, need: need) } ?? false) {
                    Effects.thought(icon: Self.icon(for: need), fallback: MoodBubbles.bubbleText(for: need),
                                    on: backend.node, height: backend.bubbleHeight)
                    tagNewestBubble(need: need)
                }
            }
            return
        }
        careCheckElapsed += dt
        guard careCheckElapsed >= 2 else { return }
        careCheckElapsed = 0
        let busy: Set<Behavior> = [.eat, .drink, .bath, .fetch, .ballChase, .greet, .yawn, .dangle, .fall, .cling, .chaseMe, .askCare,
                                   .peek]
        let fullScreen = isFullScreen(frontWindow: world.windows.first?.frame,
                                      screenFrames: NSScreen.screens.map(\.frame))
        let blocked = !askForCare || chaseMe || dragging || body.mode != .grounded || brain.current.countsAsSleep
            || busy.contains(brain.current) || ball != nil || fullScreen || userIdleSeconds > 60
        let need: Need
        if let n = careAsker.next(needs: needs.state, now: Date(), blocked: blocked,
                                  afterExercise: now - lastHardExercise < 120) {
            need = n
            careAsker.markAsked(n, at: Date())
        } else if careAsker.wantsAttention(secondsSinceInteraction: boredom.secondsSinceInteraction, now: Date(),
                                           blocked: blocked) {
            // Nobody's played with it in a while: come over and ask for a game.
            need = .happiness
            careAsker.markSoughtAttention(at: Date())
        } else {
            return
        }
        askingFor = need
        lastCareBubble = 0
        brain.interrupt(with: .askCare, duration: 14)
        beginBehavior(.askCare)
    }

    private func fulfill(_ need: Need) {
        switch need {
        case .hunger: feed()
        case .cleanliness: bath()
        case .happiness: playBall()
        case .energy: nap()
        case .thirst: drink()
        }
    }

    /// Paw patter while walking or running, and a boing when it jumps.
    private func updateMovementSounds(dt: TimeInterval) {
        let grounded = body.mode == .grounded
        if wasGrounded && body.mode == .airborne && body.velocity.dy > 0 { sounds.play(.hop) }
        wasGrounded = grounded
        guard grounded && body.isMoving else { stepElapsed = 0; return }
        stepElapsed += dt
        if stepElapsed >= (body.isRunning ? 0.16 : 0.3) {
            stepElapsed = 0
            sounds.play(.step)
        }
    }

    /// The bubble opens toward the middle of the screen, with its tail pointing back at the pet.
    private var tailRight: Bool {
        guard let i = world.screenIndex(containing: body.position) else { return false }
        return body.position.x > world.screens[i].midX
    }

    /// Shows `line`. A bubble asking for `need` can be clicked to give the pet that.
    @discardableResult
    private func say(_ line: SpeechLibrary.Line, delay: TimeInterval = 0, need: Need? = nil) -> Bool {
        if peek != nil { return false }                // quiet while hiding behind the wall
        let shown = Effects.say(line.text, bubble: line.bubble, icon: line.icon, tailRight: tailRight,
                                on: backend.node, height: backend.bubbleHeight, delay: delay)
        if shown { tagNewestBubble(need: need) }
        return shown
    }

    /// A line from the given mood, if the bundled messages have one.
    @discardableResult
    private func say(mood: String, delay: TimeInterval = 0) -> Bool {
        guard let line = speech?.line(for: mood, pet: character) else { return false }
        return say(line, delay: delay, need: SpeechLibrary.need(forCategory: mood))
    }

    /// Remembers what the bubble just added asks for, so clicking it can give the pet that.
    private func tagNewestBubble(need: Need?) {
        guard let bubble = backend.node.children.last(where: { $0.name == "bubble" }) else { return }
        bubble.userData = NSMutableDictionary(dictionary: ["need": need?.rawValue ?? ""])
    }

    /// The bubble showing right now and where it is on screen, with the need it asks about (nil: just chatting).
    private func visibleBubble() -> (node: SKNode, rect: CGRect, need: Need?)? {
        guard let b = backend.node.children.last(where: { $0.name == "bubble" && $0.alpha > 0.3 }) else { return nil }
        let f = b.calculateAccumulatedFrame(), s = drawScale
        let rect = CGRect(x: body.position.x + f.minX * s, y: body.position.y + f.minY * s,
                          width: f.width * s, height: f.height * s).insetBy(dx: -4, dy: -4)
        return (b, rect, (b.userData?["need"] as? String).flatMap(Need.init(rawValue:)))
    }

    /// Clicked a bubble: give the pet what it asked for, or just pet it for a chatty one.
    private func tapBubble(_ b: (node: SKNode, rect: CGRect, need: Need?)) {
        b.node.name = nil
        b.node.removeAllActions()
        b.node.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
        guard let need = b.need else {
            pet()
            return
        }
        boredom.noteInteraction()
        if askingFor == need { askingFor = nil }
        fulfill(need)
        say(mood: "happy", delay: 1.2)
        lastAutoLine = CACurrentMediaTime()
    }

    private func sayNow(mood: String, now: CFTimeInterval) {
        guard now - lastAutoLine >= 60 else { return }
        if say(mood: mood) { lastAutoLine = now }
    }

    /// Every 20 to 40 minutes, while you're working and it's content, it says something friendly.
    private func updateCompany(now: CFTimeInterval) {
        guard now >= nextCompany else { return }
        let content = Need.allCases.allSatisfy { needs.state[$0] >= needs.config.lowThreshold }
        let calm: Set<Behavior> = [.idle, .sit, .read, .music, .watchTV, .walk]
        guard content, body.mode == .grounded, calm.contains(brain.current), userIdleSeconds < 60 else { return }
        nextCompany = now + Double.random(in: 20 * 60...40 * 60)
        sayNow(mood: "company", now: now)
    }

    func applyProfile(_ profile: PetProfile) {
        character = profile.character
        askForCare = profile.askForCare
        // Switched off mid-request: stop asking right away.
        if !askForCare && (brain.current == .askCare || brain.current == .beg) {
            askingFor = nil
            brain.finishCurrent()
        }
        sounds.enabled = profile.soundsOn
        petSound = profile.character == .sheep ? .petSheep : .petCorgi
    }

    // MARK: Hiding behind a screen edge

    /// The draw scale the pet will have on display `i` (it eases there; see `updateDrawScale`).
    private func targetScale(on i: Int) -> CGFloat {
        displayScales.indices.contains(i) ? displayScales[i] : 1
    }

    /// Where to hide if it was just let go next to a display's outer left or right edge, when the pack has the art.
    private func edgePeekSpot() -> EdgePeek? {
        let bounds = backend.bounds(for: .peekEdge)
        let scale = world.display(at: body.position).map(targetScale(on:)) ?? drawScale
        guard let spot = EdgePeekFinder.find(feet: body.position, screens: world.screens, seams: world.seams,
                                             floors: world.segments, bounds: bounds, scale: scale,
                                             inset: backend.edgeWall?.inset ?? 0),
              backend.available.contains(spot.animState) else { return nil }
        return spot
    }

    private func startPeek(_ spot: EdgePeek) {
        peek = EdgePeekSession(spot: spot, stay: .random(in: EdgePeekSession.stay))
        let scale = targetScale(on: spot.screen)
        executor.peekStandX = spot.standX(bounds: backend.bounds(for: spot.animState), scale: scale)
        brain.interrupt(with: .peek, duration: .infinity)
        beginBehavior(.peek)
        // Put down at the edge: go straight behind the wall, with no fall, landing, walk or glide to watch.
        peek?.arrived()
        hide(spot, snap: true)
        TransitionLog.append("peek \(spot.kind.rawValue) \(spot.side.rawValue) edge x=\(Int(spot.edgeX)) y=\(Int(spot.y)) "
            + "screen \(spot.screen) from \(Int(body.position.x)),\(Int(body.position.y)) for \(Int(peek!.remaining))s"
            + (backend.edgeWall == nil ? " (no wall art)" : ""))
        // The wall slides out from behind the edge first, so there's something to hide behind.
        if let art = backend.edgeWall {
            let ground = world.ground(of: spot.screen)?.y ?? world.screens[spot.screen].minY
            let frame = spot.wallFrame(width: art.width, height: art.height, scale: scale, holdDepth: art.holdDepth,
                                       groundY: ground)
            edgeWall.show(art, frame: frame, side: spot.side, scale: scale, overlays: overlays)
        }
        if spot.kind == .hold { hide(spot) }
    }

    /// Goes behind the edge: no gravity, feet on the spot that puts the art's edge column on the screen edge.
    private func hide(_ spot: EdgePeek, snap: Bool = false) {
        body.startPeeking(at: spot.feet(bounds: backend.bounds(for: spot.animState), scale: drawScale),
                          facingRight: spot.facingRight, snap: snap)
    }

    private func updatePeek(dt: TimeInterval) {
        guard var p = peek else { return }
        let spot = p.spot
        if p.update(dt: dt) {
            endPeek(reason: "didn't reach the edge")
            brain.finishCurrent()
            return
        }
        switch p.phase {
        case .approaching:
            // Walking up to the wall (the end of the floor without one); there it turns to face the screen and hides.
            let target = spot.standX(bounds: backend.bounds(for: spot.animState), scale: drawScale)
            executor.peekStandX = target
            guard body.mode == .grounded, playback.reactionState == nil, let x = target,
                  abs(body.position.x - x) < 1, abs(body.position.y - spot.y) <= 2 else { break }
            p.arrived()
            hide(spot)
        case .peeking, .leaving:
            guard body.mode == .peeking else {
                // Picked up or knocked off; the caller already moved on.
                peek = nil
                return
            }
            // Keep the edge column on the edge while the draw scale eases.
            body.movePeek(to: spot.feet(bounds: backend.bounds(for: spot.animState), scale: drawScale))
            if spot.kind == .floor, world.segment(under: CGPoint(x: spot.floorEnd ?? body.position.x, y: spot.y)) == nil {
                endPeek(reason: "floor went away")
                brain.finishCurrent()
                return
            }
            if p.isOut(currentState: playback.currentState, transitionTarget: playback.transitionTarget) {
                peek = nil
                comeOut(p)
                return
            }
        }
        peek = p
    }

    /// The exit art has played: back to normal, standing at the end of the floor or dropping from the hold.
    private func comeOut(_ p: EdgePeekSession) {
        TransitionLog.append("peek over (\(p.spot.kind.rawValue))")
        executor.peekStandX = nil
        edgeWall.hide()
        if p.spot.kind == .floor, let x = p.spot.floorEnd,
           let floor = world.segment(under: CGPoint(x: x, y: p.spot.y)) {
            body.stopPeeking(onto: floor)
            brain.finishCurrent()
        } else {
            body.stopPeeking(onto: nil)
            brain.interrupt(with: .fall, duration: 5)
            beginBehavior(.fall)
        }
    }

    /// Cut short (picked up, fed, displays changed): out at once, without the exit art.
    private func endPeek(reason: String) {
        guard let p = peek else { return }
        peek = nil
        executor.peekStandX = nil
        TransitionLog.append("peek ended: \(reason)")
        edgeWall.hide()
        guard body.mode == .peeking else { return }
        if p.spot.kind == .floor, let x = p.spot.floorEnd,
           let floor = world.segment(under: CGPoint(x: x, y: p.spot.y)) {
            body.stopPeeking(onto: floor)
        } else {
            body.stopPeeking(onto: nil)
            sounds.play(.letGo)
            playback.requestReaction(.letGo, mode: body.mode)
        }
    }

    private func updateAnimation() {
        var state = peek?.animState ?? body.cling?.animState
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving,
                         isRunning: body.isRunning, carrying: executor.carryingBall)
        if (body.mode == .grounded || body.mode == .roaming), brain.current == .askCare && !body.isMoving {
            state = askingFor == .thirst ? .thirsty : .beg   // asking nicely
        }
        if body.mode == .grounded && brain.current == .beg && needs.state.thirst < needs.state.hunger { state = .thirsty }
        // The last two seconds of a drink are the happy "ahh".
        if (state == .eat && brain.current == .eat) || (state == .drink && brain.remaining >= Self.refreshedSeconds) {
            state = Self.bowl(state, progress: mealProgress(for: state))
        } else {
            mealStart = nil
        }
        if state.base == .drink && brain.remaining < Self.refreshedSeconds {
            state = .refreshed
            if !saidRefreshed {
                saidRefreshed = true
                say(mood: "refreshed")
            }
        }
        // A bridge holds the pet still, which would otherwise read as "stopped" and retarget it (run -> sit -> run ...).
        // Keep heading where it was going unless the behavior itself changed.
        if let target = playback.transitionTarget, playback.holdsGroundedMotion(in: body.mode),
           brain.current == transitionBehavior {
            state = target
        }
        if playback.transitionTarget == nil { transitionBehavior = brain.current }
        playback.update(state, mode: body.mode)
    }

}

extension PetController: SceneInputHandler {
    func mouseDown(at global: CGPoint) {
        // A click on a speech or thought bubble answers it.
        if !hitRect.contains(global), let b = visibleBubble(), b.rect.contains(global) {
            bubbleTapped = true
            tapBubble(b)
            return
        }
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
            sounds.play(.pickup)
            brain.interrupt(with: .dangle, duration: .infinity)
            beginBehavior(.dangle)
        }
        if dragging {
            body.moveHeld(to: CGPoint(x: global.x, y: global.y - backend.size.height * 0.8))
            refreshScreenBounds()
            clampBody()
        }
    }

    func mouseUp(at global: CGPoint) {
        defer {
            pressPoint = nil
            dragging = false
        }
        if bubbleTapped {
            bubbleTapped = false
            return
        }
        if dragging {
            body.release()
            if chaseMe {
                brain.interrupt(with: .chaseMe, duration: .infinity)
                beginBehavior(.chaseMe)
            } else if let spot = ClingFinder.find(body.position, windows: world.windows)    // where its feet are
                        ?? ClingFinder.find(global, windows: world.windows),               // or where you let go
                      let contact = ClingFinder.contact(spot, windows: world.windows),
                      rects(placementRects(world.screens, bounds: backend.bounds(for: spot.animState)), contain: contact) {
                // Dropped near a window edge: hold on to it until bored.
                body.startClinging(spot, at: contact)
                brain.interrupt(with: .cling, duration: Double.random(in: 180...360))
                beginBehavior(.cling)
            } else if let spot = edgePeekSpot() {
                // Dropped by a screen edge: it hides behind it and peeks back in for a few minutes.
                stayUntil = CACurrentMediaTime() + Self.stayPutSeconds
                stayX = body.position.x
                startPeek(spot)
            } else {
                // Stay where dropped: this spot is its home for a while.
                stayUntil = CACurrentMediaTime() + Self.stayPutSeconds
                stayX = body.position.x
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
        if peek != nil { return }
        boredom.noteInteraction()
        lastClickPet = CACurrentMediaTime()
        if brain.current == .askCare, let need = askingFor {
            askingFor = nil
            fulfill(need)
            say(mood: "happy", delay: 1.2)
            lastAutoLine = CACurrentMediaTime()
            return
        }
        if chaseMe {
            if needs.catchPet() {
                sounds.play(petSound)
                Effects.floatDoodle("heart", fallback: "❤️", on: backend.node, height: backend.size.height, count: 4)
                playback.requestReaction(.happy, mode: body.mode)
            }
            return
        }
        if brain.current.countsAsSleep {
            brain.finishCurrent()
            needs.setAsleep(false)
        }
        if needs.pet() {
            sounds.play(petSound)
            Effects.floatDoodle("heart", fallback: "❤️", on: backend.node, height: backend.size.height, count: 3)
            playback.requestReaction(.wiggle, mode: body.mode)
            if Int.random(in: 0..<4) == 0 { sayNow(mood: "happy", now: CACurrentMediaTime()) }
        }
    }
}
#endif
