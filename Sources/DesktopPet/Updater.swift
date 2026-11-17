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

    /// What a check found. `unknown` carries a sentence to show: why it couldn't tell.
    enum CheckResult: Equatable {
        case upToDate
        case available(AvailableUpdate)
        case unknown(String)
    }

    /// Asks GitHub whether there's anything newer than this build. The timed checks ignore `done`; a check the
    /// user asked for uses it to say what happened, including when it couldn't find out.
    func check(then done: ((CheckResult) -> Void)? = nil) {
        func finish(_ result: CheckResult) {
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .upToDate: self?.found(nil)
                case .available(let update): self?.found(update)
                case .unknown: break                      // keep whatever was known and try again next time
                }
                done?(result)
            }
        }
        guard let commit = builtCommit, let url = UpdateCheck.compareURL(from: commit) else {
            return finish(.unknown("This copy doesn't know which version it was built from. Rebuild it with scripts/bundle.sh."))
        }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200?:
                guard let data else { return finish(.unknown("GitHub's answer came back empty. Try again in a moment.")) }
                finish(UpdateCheck.parse(compare: data).map(CheckResult.available) ?? .upToDate)
            case 404?:
                finish(.unknown("This copy was built from a version that isn't on GitHub, so there's nothing to compare it with."))
            case 403?, 429?:
                finish(.unknown("GitHub is limiting requests right now. Try again in a little while."))
            case let code?:
                finish(.unknown("GitHub answered with an error (\(code)). Try again later."))
            case nil:
                finish(.unknown("Couldn't reach GitHub. Check your connection and try again."))
            }
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
            TransitionLog.append("update: \(update.count) new on GitHub, latest \(update.latest.prefix(7)), built from \(builtCommit?.prefix(7) ?? "?")")
            announced = update.latest
            onFound?(update)
        }
    }

    /// Pulls, rebuilds and swaps in the new app, then calls `done(true)` so the caller can relaunch it.
    /// The output goes to `logURL`.
    func install(done: @escaping (Bool) -> Void) {
        guard let update, let source = sourceDir, canInstall else { return done(false) }
        state = .updating(update)
        TransitionLog.append("update: pulling and rebuilding in \(source.path)")
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
                TransitionLog.append(ok ? "update: installed \(update.latest.prefix(7))" : "update: failed (see update.log)")
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
