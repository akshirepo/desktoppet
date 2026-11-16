#if canImport(AppKit)
import AppKit
import SpriteKit

/// Debug aid: `kill -USR1 <pid>` saves what the pet draws for the next few seconds, one PNG per tick with a line of
/// timing next to it, in ~/Library/Logs/DesktopPet/recording. For checking motion without filming the screen.
/// `kill -USR2 <pid>` runs `onDemo` (a sample bubble in each style).
final class FrameRecorder {
    static let seconds: CFTimeInterval = 12.5
    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DesktopPet/recording", isDirectory: true)
    private let queue = DispatchQueue(label: "DesktopPet.FrameRecorder")
    private var signalSources: [DispatchSourceSignal] = []
    var onDemo: (() -> Void)?
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
        for (number, action) in [(SIGUSR1, { [weak self] in self?.start() }), (SIGUSR2, { [weak self] in self?.onDemo?() })] as [(Int32, () -> Void)] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler(handler: action)
            source.resume()
            signalSources.append(source)
        }
    }

    private func start() {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        count = 0
        lines = ["frame\ttime\tx\ty\tinfo"]
        until = CACurrentMediaTime() + Self.seconds
    }

    /// Called every tick: the pet's node (pet, bubbles, effects) in a fixed box around the feet, plus `info` for the log.
    func capture(node: SKNode, global: CGPoint, info: @autoclosure () -> String) {
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
        guard let image = view.texture(from: node)?.cgImage() else { return }
        let file = dir.appendingPathComponent(String(format: "%04d.png", count))
        queue.async {
            guard let out = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(out, image, nil)
            CGImageDestinationFinalize(out)
        }
    }
}
#endif
