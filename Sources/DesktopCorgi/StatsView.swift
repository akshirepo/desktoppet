#if canImport(AppKit)
import CorgiCore
import SwiftUI

struct StatsView: View {
    let state: NeedsState
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            bar("feed", "🍖", "Hunger", state.hunger)
            bar("affection", "❤️", "Happiness", state.happiness)
            bar("sleep", "⚡️", "Energy", state.energy)
            bar("play", "🫧", "Cleanliness", state.cleanliness)
            Text("Together since \(state.firstMet.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 240)
    }

    private func bar(_ icon: String, _ fallback: String, _ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let img = Doodles.colorIcon(icon, size: 14) {
                    Image(nsImage: img)
                } else {
                    Text(fallback)
                }
                Text("\(label)  \(Int(value.rounded()))")
            }
            .font(.caption)
            ProgressView(value: value, total: 100)
                .tint(value < 30 ? .red : .accentColor)
        }
    }
}
#endif
