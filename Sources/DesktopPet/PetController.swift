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
        let frames = NSScreen.screens.map(\.visibleFrame)
        world = World(provider: CGWindowListProvider(), screens: frames, bodyBounds: backend.movementBounds)
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
        backend.spriteBounds.offsetBy(dx: body.position.x, dy: body.position.y)
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
        world.setScreens(frames)
        updateHome()
        ball?.setArea(ballArea)
    }

    private func clampBody() {
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
    }

    /// Called when the floor disappears under the corgi.
    func fell() {
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
        brain.interrupt(with: .eat, duration: 4)
        beginBehavior(.eat)
        needs.feed()
        Effects.floatDoodle("menu:feed", fallback: "🍖", on: backend.node, height: backend.size.height)
    }

    /// A few laps from the water bowl, then a happy "ahh".
    func drink() {
        wake()
        boredom.noteInteraction()
        brain.interrupt(with: .drink, duration: 6)
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
        let blocked = dragging || pressPoint != nil || (body.mode != .grounded && body.mode != .clinging)
            || brain.current.countsAsSleep || brain.current == .yawn
            || CACurrentMediaTime() - lastClickPet < hover.repeatEvery
        if hover.update(dt: dt, hovering: hitRect.contains(cursor), blocked: blocked) { hoverPet() }
    }

    private func hoverPet() {
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
                               secondsSinceInteraction: boredom.secondsSinceInteraction)
        // Do not call update with dt=0: the brain can still change behaviors at zero elapsed time.
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
        } else if executor.step(brain.current, body: body, world: world, cursor: cursor) {
            stepFinished()
        }
        // Even a planted reaction must notice a vanished floor and start falling immediately.
        if let event = body.step(dt: dt, world: world) {
            if executor.handle(event, behavior: brain.current, body: body) { stepFinished() }
            if event == .landed {
                sounds.play(.land)
                playback.requestReaction(.land, mode: body.mode)
                if brain.current == .fall { brain.finishCurrent() }
            }
            if event == .startedFalling { fell() }
        }
        clampBody()
        updateMovementSounds(dt: dt)
        let effort: Exertion = body.isRunning || (body.isMoving && brain.current.exertion == .hard) ? .hard
            : body.isMoving ? .light : .rest
        needs.exert(effort, seconds: dt)
        if effort == .hard { lastHardExercise = now }

        overlays.place(globalFeet: body.position)
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
        overlays.setClickThrough(!(body.mode == .held || hitRect.contains(cursor)))
        setRate(body.isMoving || body.mode == .held || playback.reactionState != nil || playback.transitionTarget != nil || ball != nil ? 30 : 15)
    }

    /// A thought bubble for the lowest low need, about once a minute.
    private func updateMoodBubble(dt: TimeInterval) {
        let blocked = needs.state.isAsleep || brain.current.countsAsSleep
            || body.mode == .held || body.mode == .roaming
        guard let need = moodBubbles.update(dt: dt, needs: needs.state, blocked: blocked) else { return }
        sadVariant += 1
        if say(mood: SpeechLibrary.category(for: need, variant: sadVariant)) {
            lastAutoLine = CACurrentMediaTime()
            return
        }
        Effects.thought(icon: Self.icon(for: need), fallback: MoodBubbles.bubbleText(for: need), on: backend.node,
                        height: backend.bubbleHeight)
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
            if !body.isMoving && now - lastCareBubble > 4.8 {
                if lastCareBubble == 0 {
                    sounds.play(petSound)
                    sadVariant += 1
                    careLine = speech?.line(for: SpeechLibrary.category(for: need, variant: sadVariant), pet: character)
                }
                lastCareBubble = now
                if !(careLine.map { say($0) } ?? false) {
                    Effects.thought(icon: Self.icon(for: need), fallback: MoodBubbles.bubbleText(for: need),
                                    on: backend.node, height: backend.bubbleHeight)
                }
            }
            return
        }
        careCheckElapsed += dt
        guard careCheckElapsed >= 2 else { return }
        careCheckElapsed = 0
        let busy: Set<Behavior> = [.eat, .drink, .bath, .fetch, .ballChase, .greet, .yawn, .dangle, .fall, .cling, .chaseMe, .askCare]
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

    @discardableResult
    private func say(_ line: SpeechLibrary.Line, delay: TimeInterval = 0) -> Bool {
        Effects.say(line.text, bubble: line.bubble, icon: line.icon, tailRight: tailRight,
                    on: backend.node, height: backend.bubbleHeight, delay: delay)
    }

    /// A line from the given mood, if the bundled messages have one.
    @discardableResult
    private func say(mood: String, delay: TimeInterval = 0) -> Bool {
        guard let line = speech?.line(for: mood, pet: character) else { return false }
        return say(line, delay: delay)
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
        sounds.enabled = profile.soundsOn
        petSound = profile.character == .sheep ? .petSheep : .petCorgi
    }

    private func updateAnimation() {
        var state = body.cling?.animState
            ?? animState(for: brain.current, mode: body.mode, isMoving: body.isMoving,
                         isRunning: body.isRunning, carrying: executor.carryingBall)
        if (body.mode == .grounded || body.mode == .roaming), brain.current == .askCare && !body.isMoving {
            state = askingFor == .thirst ? .thirsty : .beg   // asking nicely
        }
        if body.mode == .grounded && brain.current == .beg && needs.state.thirst < needs.state.hunger { state = .thirsty }
        // The last two seconds of a drink are the happy "ahh".
        if state == .drink && brain.remaining < 2 {
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
