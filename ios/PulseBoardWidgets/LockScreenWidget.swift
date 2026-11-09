import WidgetKit
import SwiftUI
import PulseCore

/// Lock Screen (accessory) widgets.
struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "lockscreen", intent: SelectMetricIntent.self, provider: MetricIntentProvider()) { entry in
            LockScreenWidgetView(entry: entry).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Lock Screen")
        .description("Goal progress, readiness or a metric on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot, s.isPro, let m = s.metric(entry.metric) {
            switch family {
            case .accessoryCircular:
                Gauge(value: min(1, m.progress ?? 0)) {
                    Image(systemName: m.symbol)
                } currentValueLabel: {
                    Text(compact(m)).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Label("\(m.title) \(m.formatted)", systemImage: m.symbol)
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Label(m.title, systemImage: m.symbol).font(.headline).widgetAccentable()
                    Text(m.formatted).font(.body.monospacedDigit())
                    if let r = s.score(.readiness)?.value {
                        Text("Readiness \(Int(r))").font(.caption)
                    }
                }
            }
        } else {
            Image(systemName: entry.snapshot == nil ? "heart.text.square" : "lock.fill")
                .accessibilityLabel(entry.snapshot == nil ? "Open the app to load data" : "Requires Pro")
        }
    }

    private func compact(_ m: WidgetSnapshot.Metric) -> String {
        guard let v = m.value else { return "—" }
        if v >= 10_000 { return "\((v / 1000).formatted(.number.precision(.fractionLength(0))))k" }
        if v >= 1_000 { return "\((v / 1000).formatted(.number.precision(.fractionLength(1))))k" }
        return v.formatted(.number.precision(.fractionLength(0)))
    }
}
