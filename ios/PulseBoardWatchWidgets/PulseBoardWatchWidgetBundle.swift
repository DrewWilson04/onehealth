import WidgetKit
import SwiftUI
import PulseCore

/// Watch complications (WidgetKit accessory families; ClockKit is deprecated).
@main
struct PulseBoardWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
        StepsComplication()
    }
}

struct WatchSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WatchSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSnapshotEntry { .init(date: .now, snapshot: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (WatchSnapshotEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .sample : (AppGroup.readSnapshot() ?? .sample)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSnapshotEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now, snapshot: AppGroup.readSnapshot())], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct ReadinessComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.readiness", provider: WatchSnapshotProvider()) { e in
            ReadinessComplicationView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Readiness")
        .description("Today's readiness estimate.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ReadinessComplicationView: View {
    let entry: WatchSnapshotEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let r = entry.snapshot?.score(.readiness)?.value
        switch family {
        case .accessoryCircular:
            Gauge(value: r ?? 0, in: 0...100) { Image(systemName: "gauge.with.dots.needle.67percent") } currentValueLabel: {
                Text(r.map { "\(Int($0))" } ?? "—")
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryCorner:
            Text(r.map { "\(Int($0))" } ?? "—")
                .widgetCurvesContent()
                .widgetLabel { Gauge(value: r ?? 0, in: 0...100) { Text("Ready") }.tint(Theme.bluishGreen) }
        case .accessoryInline:
            Label("Readiness \(r.map { "\(Int($0))" } ?? "—")", systemImage: "gauge.with.dots.needle.67percent")
        default:
            VStack(alignment: .leading) {
                Label("Readiness \(r.map { "\(Int($0))" } ?? "—")", systemImage: "gauge.with.dots.needle.67percent").font(.headline).widgetAccentable()
                if let s = entry.snapshot?.metric(.steps) { Text("\(s.formatted) steps").font(.caption) }
                if let c = entry.snapshot?.challenge { Text("#\(c.rank) \(c.title)").font(.caption2).lineLimit(1) }
            }
        }
    }
}

struct StepsComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "watch.steps", provider: WatchSnapshotProvider()) { e in
            StepsComplicationView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Steps")
        .description("Steps toward your goal.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct StepsComplicationView: View {
    let entry: WatchSnapshotEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let m = entry.snapshot?.metric(.steps)
        switch family {
        case .accessoryInline:
            Label("\(m?.formatted ?? "—") steps", systemImage: "figure.walk")
        case .accessoryCorner:
            Image(systemName: "figure.walk")
                .widgetLabel { Gauge(value: min(1, m?.progress ?? 0)) { Text("Steps") }.tint(Theme.orange) }
        default:
            Gauge(value: min(1, m?.progress ?? 0)) { Image(systemName: "figure.walk") } currentValueLabel: {
                Text(compact(m?.value))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
    }
    private func compact(_ v: Double?) -> String {
        guard let v else { return "—" }
        return v >= 1000 ? "\((v / 1000).formatted(.number.precision(.fractionLength(1))))k" : "\(Int(v))"
    }
}
