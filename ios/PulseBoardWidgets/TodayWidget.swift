import WidgetKit
import SwiftUI
import Charts
import PulseCore

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: SnapshotProvider()) { entry in
            TodayWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Activity rings and today's key stats.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetGate(snapshot: entry.snapshot) { s in
            switch family {
            case .systemSmall: small(s)
            case .systemLarge: large(s)
            default: medium(s)
            }
        }
    }

    private func ringsView(_ s: WidgetSnapshot, width: CGFloat) -> some View {
        Group {
            if let r = s.rings {
                RingsView(activity: r, lineWidth: width)
            } else if let steps = s.metric(.steps) {
                RingsView(rings: [.init(id: "steps", label: "Steps", progress: steps.progress ?? 0, color: Theme.orange)], lineWidth: width)
            }
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading) {
            ringsView(s, width: 8).frame(width: 64, height: 64)
            Spacer()
            if let steps = s.metric(.steps) {
                Text(steps.formatted).font(.title3.bold().monospacedDigit())
                Text("steps").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            ringsView(s, width: 10).frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                ForEach([MetricID.steps, .activeEnergy, .sleep].compactMap(s.metric)) { m in
                    row(m)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            medium(s)
            HStack {
                ForEach(s.scores, id: \.kind) { sc in
                    VStack(alignment: .leading) {
                        Text(ScoreKind(rawValue: sc.kind)?.title ?? sc.kind).font(.caption).foregroundStyle(.secondary)
                        Text(sc.value.map { "\(Int($0))" } ?? "—").font(.title2.bold().monospacedDigit())
                            .foregroundStyle(sc.value.map(Theme.scoreColor) ?? .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            ForEach([MetricID.restingHeartRate, .hrv, .water, .bodyMass].compactMap(s.metric)) { m in row(m) }
            Spacer(minLength: 0)
            Text("Updated \(s.generatedAt.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func row(_ m: WidgetSnapshot.Metric) -> some View {
        HStack(spacing: 6) {
            Image(systemName: m.symbol).foregroundStyle(accent(m.section)).frame(width: 18)
            Text(m.formatted).font(.subheadline.weight(.semibold).monospacedDigit())
            Spacer(minLength: 0)
            if let streak = m.streak, streak > 1 {
                Label("\(streak)", systemImage: "flame.fill").font(.caption2).foregroundStyle(Theme.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.title) \(m.formatted)")
    }
}

struct MetricWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "metric", intent: SelectMetricIntent.self, provider: MetricIntentProvider()) { entry in
            MetricWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Metric")
        .description("Any metric with its 7-day trend.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MetricWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        WidgetGate(snapshot: entry.snapshot) { s in
            if let m = s.metric(entry.metric) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(m.title, systemImage: m.symbol).font(.caption.weight(.semibold)).foregroundStyle(accent(m.section)).lineLimit(1)
                    Text(m.formatted).font(.title2.bold().monospacedDigit()).minimumScaleFactor(0.6)
                    if let p = m.progress {
                        ProgressView(value: min(1, p)).tint(accent(m.section))
                    }
                    Spacer(minLength: 0)
                    if m.week.count > 1 {
                        Chart(Array(m.week.enumerated()), id: \.offset) { i, v in
                            BarMark(x: .value("Day", i), y: .value("Value", v)).foregroundStyle(accent(m.section).opacity(0.8))
                        }
                        .chartXAxis(.hidden).chartYAxis(.hidden)
                        .accessibilityHidden(true)
                    }
                }
            } else {
                Text("No data").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ScoresWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "scores", provider: SnapshotProvider()) { entry in
            ScoresWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Scores")
        .description("Readiness and Sleep Score (our own estimates).")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ScoresWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        WidgetGate(snapshot: entry.snapshot) { s in
            HStack {
                ForEach(s.scores.prefix(2), id: \.kind) { sc in
                    VStack {
                        Gauge(value: sc.value ?? 0, in: 0...100) {
                            Text(ScoreKind(rawValue: sc.kind)?.title ?? "")
                        } currentValueLabel: {
                            Text(sc.value.map { "\(Int($0))" } ?? "—").monospacedDigit()
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        .tint(sc.value.map(Theme.scoreColor) ?? .secondary)
                        Text(ScoreKind(rawValue: sc.kind)?.title ?? "").font(.caption)
                        if sc.isEstimated { Text("estimated").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
