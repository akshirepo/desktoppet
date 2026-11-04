#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

public enum AnimState: String, CaseIterable, Codable {
    case idle, walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch
    case wave, back, read, readSleep, music, watch, yawn, scared, happy, holdBall, kick, roam
    case clingSit, clingHang, clingPeek, clingLeft, clingRight, letGo, drink, thirsty, refreshed
    /// The same eating and drinking loops with the bowl half empty and empty.
    case eatHalf, eatEmpty, drinkHalf, drinkEmpty
    /// Hiding behind a display's left or right edge and peeking back in: on the floor (head and front paws round
    /// the edge) and hanging on to the edge higher up. See `EdgePeek` for the art convention.
    case peekEdge, holdEdge

    /// The loop a variant is drawn from (eatHalf -> eat); itself for everything else.
    public var base: AnimState {
        switch self {
        case .eatHalf, .eatEmpty: return .eat
        case .drinkHalf, .drinkEmpty: return .drink
        default: return self
        }
    }
}

public struct AnimationSpec: Codable, Equatable {
    public var folder: String
    public var fps: Double
    public var loop: Bool
    public var anchor: [Double]
    /// Overrides the shared posture for this pet, e.g. a sheep that eats standing up.
    public var posture: Posture?
    /// Plays the folder's frames last to first, e.g. sit-to-stand from the stand-to-sit frames.
    public var reversed: Bool?
    /// Size correction for a pose drawn at a different scale than the rest of the pack (0.8 = draw 20% smaller).
    public var scale: Double?

    public init(folder: String, fps: Double, loop: Bool, anchor: [Double], posture: Posture? = nil, reversed: Bool? = nil) {
        self.folder = folder
        self.fps = fps
        self.loop = loop
        self.anchor = anchor
        self.posture = posture
        self.reversed = reversed
    }
}

/// The wall a pet hides behind at a screen edge (see `EdgePeek`). Sizes are canvas pixels at the pack scale.
/// The folder holds `cap.png` (the top), `tile.png` (repeated below it) and optionally `base.png` (a footing at the
/// bottom), all `width` wide, drawn for a LEFT screen edge (outer side on column 0, inner face on the right);
/// the app mirrors them.
public struct EdgeWallSpec: Codable, Equatable {
    public var folder: String
    /// From the screen edge to the wall's inner face.
    public var width: Double
    /// How far the top of the wall is above the pet's feet.
    public var height: Double
    /// The column of the peek frames (`peekEdge`, `holdEdge` and their bridges) that sits on the wall's inner
    /// face. The body is cut there; paws drawn left of it hook over the wall.
    public var faceColumn: Double
    /// Hanging on (`holdEdge`), how far below the feet the wall section reaches; it's a short piece of wall around
    /// the grip, not a wall from the floor. Without it the hold wall runs down to the display's floor.
    public var holdDepth: Double?

    public init(folder: String, width: Double, height: Double, faceColumn: Double, holdDepth: Double? = nil) {
        self.folder = folder
        self.width = width
        self.height = height
        self.faceColumn = faceColumn
        self.holdDepth = holdDepth
    }

    /// Points (before the display scale) from the screen edge to column 0 of the peek frames.
    public func inset(packScale: Double) -> CGFloat { CGFloat((width - faceColumn) * packScale) }
}

public enum AnimationManifestError: Error, Equatable {
    case missingIdle
}

public struct AnimationManifest: Codable, Equatable {
    public var scale: Double?
    public var states: [String: AnimationSpec]

    public static func load(from url: URL) throws -> AnimationManifest {
        let m = try JSONDecoder().decode(AnimationManifest.self, from: Data(contentsOf: url))
        guard m.states[AnimState.idle.rawValue] != nil else { throw AnimationManifestError.missingIdle }
        return m
    }

    public func resolve(_ state: AnimState) -> (state: AnimState, spec: AnimationSpec)? {
        if let spec = states[state.rawValue] { return (state, spec) }
        if state.base != state { return resolve(state.base) }
        // Packs without the hydration art borrow the closest older pose.
        let stand: [AnimState: AnimState] = [.drink: .eat, .thirsty: .beg, .refreshed: .happy]
        if let alt = stand[state], let spec = states[alt.rawValue] { return (alt, spec) }
        if let idle = states[AnimState.idle.rawValue] { return (.idle, idle) }
        return nil
    }

    /// One-shot transition animations by name (see `Bridge`), e.g. "stand>sit" or "enter:watch".
    public var bridges: [String: AnimationSpec]?
    /// Activities drawn from the same view (e.g. a side-on walk, run and kick) that switch into each other directly.
    public var directGroups: [[String]]?
    /// The wall it hides behind when peeking round a screen edge. Without one it peeks round the bare edge.
    public var edgeWall: EdgeWallSpec?

    /// Every ordered pair inside a direct group.
    public var directPairs: Set<[AnimState]> {
        var pairs: Set<[AnimState]> = []
        for group in directGroups ?? [] {
            let states = group.compactMap(AnimState.init(rawValue:))
            for a in states { for b in states where a != b { pairs.insert([a, b]) } }
        }
        return pairs
    }

    /// States this pack has art for.
    public var available: Set<AnimState> { Set(states.keys.compactMap(AnimState.init(rawValue:))) }

    /// Shared postures with this pack's overrides applied.
    public var postures: [AnimState: Posture] {
        var p = Posture.defaults
        for (key, spec) in states {
            if let state = AnimState(rawValue: key), let override = spec.posture { p[state] = override }
        }
        for s in AnimState.allCases where s.base != s { p[s] = p[s.base] }
        return p
    }

    public var missingStates: [AnimState] {
        AnimState.allCases.filter { states[$0.rawValue] == nil }
    }
}

public func animState(for behavior: Behavior, mode: BodyMode, isMoving: Bool,
                      isRunning: Bool = false, carrying: Bool = false) -> AnimState {
    switch mode {
    case .held: return .scared
    case .airborne: return .fall
    case .roaming: return carrying ? .holdBall : .roam
    case .clinging: return .clingSit   // callers with the spot use ClingSpot.animState
    case .peeking: return .peekEdge    // callers with the session use EdgePeekSession.animState
    case .grounded: break
    }
    if isMoving {
        switch behavior {
        case .zoomies, .chaseCursor, .fetch, .greet: return .run
        default: return isRunning ? .run : .walk
        }
    }
    switch behavior {
    case .sit, .chaseCursor: return .sit
    case .sleep, .idleSleep: return .sleep
    case .beg: return .beg
    case .eat: return .eat
    case .drink: return .drink
    case .bath: return .bath
    case .fetch: return .fetch
    case .greet, .wave: return .wave
    case .dangle: return .dangle
    case .fall: return .fall
    case .turnAround: return .back
    case .read: return .read
    case .readSleep: return .readSleep
    case .music: return .music
    case .watchTV: return .watch
    case .yawn: return .yawn
    case .playBallHome: return .kick
    default: return .idle
    }
}
