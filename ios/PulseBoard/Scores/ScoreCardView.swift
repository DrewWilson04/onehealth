import SwiftUI
import PulseCore
import PulseKit

/// Dashboard tile for a derived score.
struct ScoreCardView: View {
    let kind: ScoreKind
    let result: ScoreResult?
    let locked: Bool

    var body: some View {
        CardContainer(tint: Theme.bluishGreen) {
            VStack(alignment: .leading, spacing: 6) {
                Label(kind.title, systemImage: kind.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.bluishGreen)
                if locked {
                    Label("Pro", systemImage: "lock.fill").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Unlock \(kind.title) with Pro").font(.caption).foregroundStyle(.secondary)
                } else if let r = result, let v = r.value {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(kind == .strain ? v.formatted(.number.precision(.fractionLength(1))) : "\(Int(v.rounded()))")
                            .font(.title.bold().monospacedDigit())
                            .foregroundStyle(kind == .strain ? Theme.orange : Theme.scoreColor(v))
                        Text(kind == .strain ? "/ 21" : "/ 100").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(r.label).font(.caption.weight(.medium))
                    if kind == .strain, let status = r.reason { Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    if r.isEstimated { EstimatedBadge(confidence: r.confidence) }
                } else {
                    Text("—").font(.title.bold())
                    Text(result?.reason ?? "Not enough data").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        if locked { return "\(kind.title), requires Pro" }
        guard let v = result?.value else { return "\(kind.title), not enough data" }
        return "\(kind.title) \(Int(v.rounded())), \(result?.label ?? "")\(result?.isEstimated == true ? ", estimated" : ""). Our own estimate."
    }
}
