import XCTest
@testable import CorgiCore

final class HomeTests: XCTestCase {
    let screen1 = CGRect(x: 1440, y: 0, width: 1920, height: 1000)

    func testHomeIsBottomRightOfMainVisibleFrame() {
        let home = HomeTracker(clock: FakeClock())
        home.setScreens([screen0, screen1], mainIndex: 1)
        XCTAssertEqual(home.spot, CGPoint(x: 3360 - 80, y: 0))
        home.setScreens([CGRect(x: 0, y: 70, width: 1440, height: 805)], mainIndex: 0)  // Dock at the bottom
        XCTAssertEqual(home.spot, CGPoint(x: 1360, y: 70))
    }

    func testHomeMovesWhenItsMonitorIsUnplugged() {
        let home = HomeTracker(clock: FakeClock())
        home.setScreens([screen0, screen1], mainIndex: 1)
        home.setScreens([screen0], mainIndex: 1)          // main index now out of range
        XCTAssertEqual(home.spot, CGPoint(x: 1360, y: 0))
        home.setScreens([], mainIndex: 0)
        XCTAssertNil(home.spot)
        XCTAssertFalse(home.isHome(CGPoint(x: 1360, y: 0)))
    }

    func testIsHomeUsesRadiusAndSameFloor() {
        let home = HomeTracker(clock: FakeClock())
        home.setScreens([screen0], mainIndex: 0)
        XCTAssertTrue(home.isHome(CGPoint(x: 1330, y: 0)))
        XCTAssertFalse(home.isHome(CGPoint(x: 1300, y: 0)))
        XCTAssertFalse(home.isHome(CGPoint(x: 1360, y: 300)))   // on a window above home
    }

    func testTimeAwayCountsAndResetsAtHome() {
        let clock = FakeClock()
        let home = HomeTracker(clock: clock)
        home.setScreens([screen0], mainIndex: 0)
        home.observe(CGPoint(x: 200, y: 0))
        clock.advance(90)
        home.observe(CGPoint(x: 400, y: 0))
        XCTAssertEqual(home.secondsAway, 90, accuracy: 0.001)
        home.observe(CGPoint(x: 1360, y: 0))
        XCTAssertEqual(home.secondsAway, 0)
    }

    func testTimeAwayNeverNegativeWhenClockGoesBack() {
        let clock = FakeClock()
        let home = HomeTracker(clock: clock)
        home.setScreens([screen0], mainIndex: 0)
        home.observe(CGPoint(x: 200, y: 0))
        clock.advance(-600)
        XCTAssertEqual(home.secondsAway, 0)
    }

    func testGreetingLines() {
        XCTAssertEqual(Greeting.lines(awaySeconds: 0), ["Hi!"])
        XCTAssertEqual(Greeting.lines(awaySeconds: 3601), ["Hi!", "Missed you!"])
    }
}
