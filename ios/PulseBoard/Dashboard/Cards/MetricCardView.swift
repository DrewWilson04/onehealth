import SwiftUI
import Charts
import PulseCore

/// A metric tile: today's value, 7-day sparkline, week-over-week change,
/// source badge and estimated marker.
struct MetricCardView: View {
    let metric: MetricType
    let snapshot: DashboardModel.MetricSnapshot?
    var size: DashboardCard.Size = .small

    private var accent: Color { Theme.accent(metric.section) }
    private var shown: DailyAggregate? {
        metric.dailyStatistic == .latest ? (snapshot?.latest) : (snapshot?.today ?? nil)
    }
    private var value: Double? { shown?.value(for: metric.dailyStatistic) }

    var body: some View {
        CardContainer(tint: accent) {
            VStack(alignment: .leading, spacing: 6) {
                Label(metric.displayName, systemImage: metric.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                Text(Fmt.value(value, metric: metric))
                    .font(.title2.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                subtitle
                if let pts = snapshot?.week, pts.count > 1 {
                    Chart(pts) { p in
                        if metric.kind == .cumulative || metric.kind == .workout {
                            BarMark(x: .value("Day", p.day.date(), unit: .day), y: .value(metric.displayName, p.value))
                                .foregroundStyle(accent.opacity(p.isEstimated ? 0.35 : 0.85))
                                .cornerRadius(2)
                        } else {
                            LineMark(x: .value("Day", p.day.date(), unit: .day), y: .value(metric.displayName, p.value))
                                .foregroundStyle(accent)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: metric.kind == .cumulative))
                    .frame(height: size == .small ? 34 : 60)
                    .accessibilityHidden(true)
                }
                HStack(spacing: 6) {
                    SourceBadge(sourceKey: shown?.primarySource)
                    if shown?.isEstimated == true { EstimatedBadge(confidence: shown?.confidence) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var subtitle: some View {
        if value == nil {
            Text("No data today").font(.caption).foregroundStyle(.secondary)
        } else if metric.dailyStatistic == .latest, let d = shown?.day, d != DayKey.today() {
            Text(Fmt.day(d)).font(.caption).foregroundStyle(.secondary)
        } else if let c = snapshot?.comparison, let pct = c.percentChange {
            let dir = c.direction(higherIsBetter: metric.higherIsBetter)
            Label("\(pct >= 0 ? "+" : "")\(pct.formatted(.percent.precision(.fractionLength(0)))) vs last week",
                  systemImage: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.caption)
                .foregroundStyle(dir > 0 ? Theme.bluishGreen : (dir < 0 ? Theme.vermillion : .secondary))
        }
    }

    private var accessibilityText: String {
        var s = "\(metric.displayName), \(Fmt.value(value, metric: metric))"
        if let pct = snapshot?.comparison?.percentChange {
            s += ", \(pct >= 0 ? "up" : "down") \(abs(pct).formatted(.percent.precision(.fractionLength(0)))) versus last week"
        }
        if shown?.isEstimated == true { s += ", estimated" }
        return s
    }
}
