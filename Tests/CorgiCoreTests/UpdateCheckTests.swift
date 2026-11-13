import XCTest
@testable import CorgiCore

final class UpdateCheckTests: XCTestCase {
    func testNewerCommitsAreAnUpdateNewestFirst() throws {
        let json = """
        {"status": "ahead", "ahead_by": 2, "commits": [
          {"sha": "aaa", "commit": {"message": "Smaller bubbles\\n\\nDetails here"}},
          {"sha": "bbb", "commit": {"message": "Run in after switching Spaces"}}]}
        """
        let update = try XCTUnwrap(UpdateCheck.parse(compare: Data(json.utf8)))
        XCTAssertEqual(update, AvailableUpdate(latest: "bbb", count: 2,
                                               titles: ["Run in after switching Spaces", "Smaller bubbles"]))
    }

    func testUpToDateOrAheadIsNoUpdate() {
        XCTAssertNil(UpdateCheck.parse(compare: Data(#"{"status": "identical", "ahead_by": 0, "commits": []}"#.utf8)))
        XCTAssertNil(UpdateCheck.parse(compare: Data(#"{"status": "behind", "ahead_by": 0, "behind_by": 3, "commits": []}"#.utf8)))
    }

    func testUnknownCommitOrErrorIsNoUpdate() {
        XCTAssertNil(UpdateCheck.parse(compare: Data(#"{"message": "Not Found"}"#.utf8)))
        XCTAssertNil(UpdateCheck.parse(compare: Data("not json".utf8)))
    }

    func testCompareURL() {
        XCTAssertEqual(UpdateCheck.compareURL(from: "abc123")?.absoluteString,
                       "https://api.github.com/repos/akshirepo/desktoppet/compare/abc123...main")
    }
}
