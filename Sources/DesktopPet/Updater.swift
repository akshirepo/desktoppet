#if canImport(AppKit)
import AppKit
import CorgiCore

/// Looks on GitHub for commits newer than this build, and installs them by pulling and rebuilding the clone it was
/// built from. `bundle.sh` records that commit and folder in Info.plist as DPCommit and DPSourceDir.
final class Updater {
    enum State: Equatable {
        case upToDate
        case available(AvailableUpdate)
        case updating(AvailableUpdate)
        case failed(AvailableUpdate)
    }

    private(set) var state: State = .upToDate {
        didSet { if state != oldValue { onChange?() } }
    }
    var onChange: (() -> Void)?
    /// Called once for each new latest commit it finds.
    var onFound: ((AvailableUpdate) -> Void)?

    let builtCommit = (Bundle.main.object(forInfoDictionaryKey: "DPCommit") as? String).flatMap { $0.isEmpty ? nil : $0 }
    let sourceDir = (Bundle.main.object(forInfoDictionaryKey: "DPSourceDir") as? String).map { URL(fileURLWithPath: $0) }
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DesktopPet/update.log")
    static let changesURL = URL(string: "https://github.com/\(UpdateCheck.repo)/commits/\(UpdateCheck.branch)")!
    private var timer: Timer?
    private var announced: String?

    var update: AvailableUpdate? {
        switch state {
        case .upToDate: return nil
        case .available(let u), .updating(let u), .failed(let u): return u
        }
    }

    /// The clone is still there, so it can update itself; otherwise it can only point at GitHub.
    var canInstall: Bool {
        sourceDir.map { FileManager.default.isExecutableFile(atPath: $0.appendingPathComponent("scripts/bundle.sh").path) } ?? false
    }

    func start() {
        guard builtCommit != nil else {
            NSLog("DesktopPet: built without a commit id, so it can't check for updates")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check() {
        guard let commit = builtCommit, let url = UpdateCheck.compareURL(from: commit) else { return }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            // Offline, rate limited, or a local commit GitHub doesn't have: try again next time.
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data else { return }
            let found = UpdateCheck.parse(compare: data)
            DispatchQueue.main.async { self?.found(found) }
        }.resume()
    }

    private func found(_ update: AvailableUpdate?) {
        if case .updating = state { return }
        guard let update else {
            state = .upToDate
            return
        }
        state = .available(update)
        if announced != update.latest {
            announced = update.latest
            onFound?(update)
        }
    }

    /// Pulls, rebuilds and swaps in the new app, then calls `done(true)` so the caller can relaunch it.
    /// The output goes to `logURL`.
    func install(done: @escaping (Bool) -> Void) {
        guard let update, let source = sourceDir, canInstall else { return done(false) }
        state = .updating(update)
        let script = """
        set -euo pipefail
        echo "== $(date) updating from $1"
        cd "$1"
        git pull --ff-only origin \(UpdateCheck.branch)
        ./scripts/bundle.sh
        case "$3" in *.app) ;; *) echo "not replacing $3"; exit 1 ;; esac
        if [ "$2" != "$3" ]; then
          rm -rf "$3.new"
          ditto "$2" "$3.new"
          rm -rf "$3"
          mv "$3.new" "$3"
        fi
        echo "== updated"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "update", source.path,
                             source.appendingPathComponent("build/DesktopPet.app").path, Bundle.main.bundleURL.path]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        process.environment = env
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Self.logURL.path) { fm.createFile(atPath: Self.logURL.path, contents: nil) }
        let log = try? FileHandle(forWritingTo: Self.logURL)
        _ = try? log?.seekToEnd()
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                try? log?.close()
                let ok = p.terminationStatus == 0
                self?.state = ok ? .upToDate : .failed(update)
                done(ok)
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("DesktopPet: couldn't start the update: \(error)")
            state = .failed(update)
            done(false)
        }
    }
}
#endif
