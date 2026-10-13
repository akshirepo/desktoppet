#if canImport(AppKit)
import AppKit

/// Built-in macOS system sounds only, at low volume, and only when the Sounds toggle is on.
final class SoundPlayer {
    enum Effect: String { case pop = "Pop", tink = "Tink", purr = "Purr", bottle = "Bottle" }

    var enabled = false
    private var cache: [Effect: NSSound] = [:]

    func play(_ effect: Effect) {
        guard enabled else { return }
        guard let sound = cache[effect] ?? NSSound(named: NSSound.Name(effect.rawValue)) else {
            NSLog("DesktopCorgi: system sound \(effect.rawValue) not found")
            return
        }
        cache[effect] = sound
        sound.volume = 0.3
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
#endif
