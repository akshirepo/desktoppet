import Foundation
@testable import CorgiCore

final class FakeClock: Clock {
    var now: Date
    init(_ now: Date = Date(timeIntervalSince1970: 1_000_000)) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
