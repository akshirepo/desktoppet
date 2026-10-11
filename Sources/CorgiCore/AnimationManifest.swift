import Foundation

public enum AnimState: String, CaseIterable, Codable {
    case idle, walk, run, sit, sleep, eat, beg, dangle, fall, land, wiggle, bath, fetch
}

public struct AnimationSpec: Codable, Equatable {
    public var folder: String
    public var fps: Double
    public var loop: Bool
    public var anchor: [Double]

    public init(folder: String, fps: Double, loop: Bool, anchor: [Double]) {
        self.folder = folder
        self.fps = fps
        self.loop = loop
        self.anchor = anchor
    }
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
        if let idle = states[AnimState.idle.rawValue] { return (.idle, idle) }
        return nil
    }

    public var missingStates: [AnimState] {
        AnimState.allCases.filter { states[$0.rawValue] == nil }
    }
}

public func animState(for behavior: Behavior, mode: BodyMode, isMoving: Bool) -> AnimState {
    switch mode {
    case .held: return .dangle
    case .airborne: return .fall
    case .grounded: break
    }
    if isMoving {
        switch behavior {
        case .zoomies, .chaseCursor, .fetch, .greet: return .run
        default: return .walk
        }
    }
    switch behavior {
    case .sit, .chaseCursor: return .sit
    case .sleep: return .sleep
    case .beg: return .beg
    case .eat: return .eat
    case .bath: return .bath
    case .fetch: return .fetch
    case .greet: return .wiggle
    case .dangle: return .dangle
    case .fall: return .fall
    default: return .idle
    }
}
