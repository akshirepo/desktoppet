import Foundation

/// Newer commits on GitHub than the ones this copy was built from.
public struct AvailableUpdate: Equatable {
    /// The newest commit on the branch.
    public var latest: String
    /// How many commits ahead of this build it is.
    public var count: Int
    /// First line of each new commit message, newest first.
    public var titles: [String]

    public init(latest: String, count: Int, titles: [String]) {
        self.latest = latest
        self.count = count
        self.titles = titles
    }
}

public enum UpdateCheck {
    public static let repo = "akshirepo/desktoppet"
    public static let branch = "main"

    /// GitHub's compare of the built commit against the branch.
    public static func compareURL(from built: String) -> URL? {
        URL(string: "https://api.github.com/repos/\(repo)/compare/\(built)...\(branch)")
    }

    /// Reads a compare response. Nil when nothing is newer, including a build ahead of the branch.
    public static func parse(compare data: Data) -> AvailableUpdate? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ahead = json["ahead_by"] as? Int, ahead > 0,
              let commits = json["commits"] as? [[String: Any]], let last = commits.last?["sha"] as? String
        else { return nil }
        let titles = commits.reversed().compactMap {
            (($0["commit"] as? [String: Any])?["message"] as? String)?
                .split(separator: "\n", maxSplits: 1).first.map(String.init)
        }
        return AvailableUpdate(latest: last, count: ahead, titles: titles)
    }
}
