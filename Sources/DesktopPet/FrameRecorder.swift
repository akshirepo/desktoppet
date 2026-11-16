#if canImport(AppKit)
import AppKit
import SpriteKit

/// Debug aid: `kill -USR1 <pid>` saves what the pet draws for the next few seconds, one PNG per tick with a line of
/// timing next to it, in ~/Library/Logs/DesktopPet/recording. For checking motion without filming the screen.
final class FrameRecorder {
    static let seconds: CFTimeInterval = 12
    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DesktopPet/recording", isDirectory: true)
    private let queue = DispatchQueue(label: "DesktopPet.FrameRecorder")
    private var signalSource: DispatchSourceSignal?
    private var until: CFTimeInterval = 0
    private var count = 0
    private var lines: [String] = []

    func listen() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.start() }
        source.resume()
        signalSource = source
    }

    private func start() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        count = 0
        lines = ["frame\ttime\tx\ty\tinfo"]
        until = CACurrentMediaTime() + Self.seconds
    }

    /// Called every tick: a 300x260 pt view around the feet, plus `info` for the log.
    func capture(scene: SKScene?, feet: CGPoint, global: CGPoint, info: @autoclosure () -> String) {
        guard until > 0 else { return }
        let now = CACurrentMediaTime()
        guard now < until, let scene, let view = scene.view else {
            until = 0
            let text = lines.joined(separator: "\n") + "\n"
            let file = dir.appendingPathComponent("frames.tsv")
            queue.async { try? text.write(to: file, atomically: true, encoding: .utf8) }
            return
        }
        count += 1
        lines.append(String(format: "%04d\t%.4f\t%.2f\t%.2f\t", count, now, global.x, global.y) + info())
        let crop = CGRect(x: feet.x - 150, y: feet.y - 60, width: 300, height: 260)
        guard let image = view.texture(from: scene, crop: crop)?.cgImage() else { return }
        let file = dir.appendingPathComponent(String(format: "%04d.png", count))
        queue.async {
            guard let out = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(out, image, nil)
            CGImageDestinationFinalize(out)
        }
    }
}
#endif
