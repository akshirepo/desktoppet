#if canImport(AppKit)
import AppKit

/// The pet's sound effects (Assets/Sounds, bundled under Contents/Resources/Sounds). Only plays when Sounds is on.
final class SoundPlayer {
    enum Effect: String {
        case petCorgi = "pet_corgi", petSheep = "pet_sheep", happy, eat, bath, snore, yawn, step, hop, land
        case ballBounce = "ball_bounce", ballCatch = "ball_catch", ballPop = "ball_pop", pickup, letGo = "letgo"

        /// Quiet for the repeating ones so they stay in the background.
        var volume: Float {
            switch self {
            case .step: return 0.18
            case .snore: return 0.3
            case .land, .hop: return 0.35
            default: return 0.5
            }
        }
    }

    var enabled = false
    private var cache: [Effect: NSSound] = [:]
    private let folder = Bundle.main.resourceURL?.appendingPathComponent("Sounds")

    func play(_ effect: Effect) {
        guard enabled else { return }
        guard let sound = cache[effect] ?? load(effect) else { return }
        cache[effect] = sound
        sound.volume = effect.volume
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    private func load(_ effect: Effect) -> NSSound? {
        guard let url = folder?.appendingPathComponent("\(effect.rawValue).wav"),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            NSLog("DesktopCorgi: missing sound \(effect.rawValue).wav")
            return nil
        }
        return sound
    }
}
#endif
