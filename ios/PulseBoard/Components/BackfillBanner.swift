import SwiftUI
import PulseKit

/// Non-blocking banner shown while history is importing.
struct BackfillBanner: View {
    @Environment(IngestionStatus.self) private var status

    var body: some View {
        if status.isBackfilling || status.phase == .paused {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: status.phase == .paused ? "pause.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(status.progress, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: status.progress)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title), \(Int(status.progress * 100)) percent")
        }
    }

    private var title: String {
        switch status.phase {
        case .recent: return "Loading recent data"
        case .history: return "Importing your history"
        case .paused: return "Import paused"
        default: return "Importing"
        }
    }

    private var detail: String? {
        if status.phase == .paused { return status.lastError ?? "Resumes automatically." }
        var parts: [String] = []
        if let m = status.currentMetric { parts.append(m) }
        if let d = status.oldestIngested, status.phase == .history {
            parts.append("back to \(d.formatted(.dateTime.month(.abbreviated).year()))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
