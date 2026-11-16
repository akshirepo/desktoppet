#if canImport(AppKit)
import AppKit
import SpriteKit

/// Debug aid: `kill -USR1 <pid>` saves what the pet draws for the next few seconds, one PNG per tick with a line of
/// timing next to it, in ~/Library/Logs/DesktopPet/recording. For checking motion without filming the screen.
/// `kill -USR2 <pid>` runs `onReplay` with the word in ~/Library/Logs/DesktopPet/replay (empty if there's no file).
final class FrameRecorder {
    static let seconds: CFTimeInterval = 12
    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DesktopPet/recording", isDirectory: true)
    private let queue = DispatchQueue(label: "DesktopPet.FrameRecorder")
    private var signalSources: [DispatchSourceSignal] = []
    /// What `kill -USR2 <pid>` does: replays a moment worth recording.
    var onReplay: ((String) -> Void)?
    /// Keeps every captured frame the same size, with the feet at the same spot.
    private let frameBox: SKSpriteNode = {
        let box = SKSpriteNode(color: .clear, size: CGSize(width: 320, height: 260))
        box.position = CGPoint(x: 0, y: 80)
        box.zPosition = -100
        return box
    }()
    private var until: CFTimeInterval = 0
    private var count = 0
    private var lines: [String] = []

    func listen() {
        for (number, action) in [(SIGUSR1, { [weak self] in self?.start() }), (SIGUSR2, { [weak self] in self?.replay() })] as [(Int32, () -> Void)] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler(handler: action)
            source.resume()
            signalSources.append(source)
        }
    }

    private func replay() {
        let file = dir.deletingLastPathComponent().appendingPathComponent("replay")
        let word = (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        onReplay?(word)
    }

    private func start() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        count = 0
        lines = ["frame\ttime\tx\ty\tinfo"]
        until = CACurrentMediaTime() + Self.seconds
    }

    /// Called every tick: the pet's node (pet, bubbles, effects) in a fixed box around the feet, plus `info` for the log.
    func capture(node: SKNode, mirror: SKSpriteNode? = nil, global: CGPoint, info: @autoclosure () -> String) {
        guard until > 0 else { return }
        let now = CACurrentMediaTime()
        guard now < until, let view = node.scene?.view else {
            until = 0
            frameBox.removeFromParent()
            let text = lines.joined(separator: "\n") + "\n"
            let file = dir.appendingPathComponent("frames.tsv")
            queue.async { try? text.write(to: file, atomically: true, encoding: .utf8) }
            return
        }
        count += 1
        lines.append(String(format: "%04d\t%.4f\t%.2f\t%.2f\t", count, now, global.x, global.y) + info())
        if frameBox.parent !== node {
            frameBox.removeFromParent()
            node.addChild(frameBox)
        }
        var shots: [(String, CGImage)] = []
        if let image = view.texture(from: node)?.cgImage() { shots.append((String(format: "%04d.png", count), image)) }
        // The copy drawn on the neighbouring display while the pet reaches across the seam.
        if let mirror, let other = mirror.scene?.view, let image = other.texture(from: mirror)?.cgImage() {
            shots.append((String(format: "%04d-copy.png", count), image))
        }
        let dir = self.dir
        queue.async {
            for (name, image) in shots {
                guard let out = CGImageDestinationCreateWithURL(dir.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil) else { continue }
                CGImageDestinationAddImage(out, image, nil)
                CGImageDestinationFinalize(out)
            }
        }
    }
}
#endif
