#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// True when the frontmost window covers a whole screen (its full frame, not the visible frame).
public func isFullScreen(frontWindow: CGRect?, screenFrames: [CGRect], tolerance: CGFloat = 1) -> Bool {
    guard let w = frontWindow else { return false }
    return screenFrames.contains {
        abs($0.minX - w.minX) <= tolerance && abs($0.minY - w.minY) <= tolerance
            && abs($0.width - w.width) <= tolerance && abs($0.height - w.height) <= tolerance
    }
}

public enum RestEvent: Equatable { case startYawn, fallAsleep, wake }

/// Decides when the corgi rests because the user is away (yawn, then sleep) or a full screen
/// app is in front (sleep right away). Separate from energy-based napping.
public final class RestMonitor {
    public enum Phase: Equatable { case awake, yawning, asleep }

    public var idleThreshold: TimeInterval = 90
    public var yawnDuration: TimeInterval = 2
    public private(set) var phase: Phase = .awake
    private var yawnLeft: TimeInterval = 0

    public init() {}

    /// - Parameters:
    ///   - idleSeconds: seconds since the last keyboard or mouse event.
    ///   - fullScreen: a full screen window is in front.
    ///   - busy: the corgi is held, in Chase Me, or chasing a ball. Busy never rests and wakes a rest.
    public func update(dt: TimeInterval, idleSeconds: TimeInterval, fullScreen: Bool, busy: Bool) -> RestEvent? {
        let wantsRest = !busy && (idleSeconds >= idleThreshold || fullScreen)
        switch phase {
        case .awake:
            guard wantsRest else { return nil }
            if fullScreen {
                phase = .asleep
                return .fallAsleep
            }
            phase = .yawning
            yawnLeft = yawnDuration
            return .startYawn
        case .yawning:
            guard wantsRest else {
                phase = .awake
                return .wake
            }
            yawnLeft -= dt
            guard yawnLeft <= 0 else { return nil }
            phase = .asleep
            return .fallAsleep
        case .asleep:
            guard !wantsRest else { return nil }
            phase = .awake
            return .wake
        }
    }
}
