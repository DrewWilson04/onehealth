import SwiftUI
import Charts
import PulseCore
import PulseKit

struct MetricDetailView: View {
    let metric: MetricType
    @Environment(AppServices.self) private var services
    @Environment(EntitlementManager.self) private var entitlements
    @Environment(IngestionStatus.self) private var status
    @State private var model: MetricTrendModel
    @State private var showRolling = true
    @State private var showPaywall = false
    @State private var selected: TrendPoint?
    @State private var notes: [Finding] = []

    init(metric: MetricType) {
        self.metric = metric
        _model = State(initialValue: MetricTrendModel(metric: metric))
    }

    private var accent: Color { Theme.accent(metric.section) }
    private var calendar: Calendar { services.calendar }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: rangeBinding) {
                    ForEach(TrendRange.allCases) { r in
                        Text(r.requiresPro && !entitlements.isEnabled(.fullHistoryTrends) ? "\(r.rawValue) 🔒" : r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Time range")

                header
                chart.frame(height: 240)
                if model.range == .week || model.range == .month {
                    Toggle("7-day average", isOn: $showRolling).font(.subheadline)
                }
            }

            if !notes.isEmpty {
                Section("Notable") {
                    ForEach(notes) { n in
                        Label(n.text, systemImage: n.kind == .anomaly ? "exclamationmark.circle" : "chart.line.uptrend.xyaxis")
                            .font(.subheadline)
                    }
                }
            }

            if let w = model.weekComparison, w.current != nil {
                Section("Compared with last period") {
                    ComparisonRow(title: "This week vs last week", comparison: w, metric: metric)
                    if let m = model.monthComparison, m.current != nil {
                        ComparisonRow(title: "This month vs last month", comparison: m, metric: metric)
                    }
                }
            }

            if !model.bests.isEmpty {
                Section("Personal bests") {
                    ForEach(model.bests, id: \.period) { b in
                        LabeledContent {
                            VStack(alignment: .trailing) {
                                Text(Fmt.value(b.value, metric: metric)).font(.body.monospacedDigit())
                                Text(bestDate(b)).font(.caption).foregroundStyle(.secondary)
                            }
                        } label: {
                            Label(b.period == .day ? "Best day" : (b.period == .week ? "Best week" : "Best month"), systemImage: "trophy.fill")
                                .foregroundStyle(Theme.orange)
                        }
                    }
                }
            }

            Section {
                Text(about).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(metric.displayName)
        .tint(accent)
        .task(id: "\(model.range.rawValue)-\(status.dataRevision)") { await model.load(services: services) }
        .task(id: status.dataRevision) {
            let key = metric.id == .sleep ? "sleepMinutes" : metric.id.rawValue
            notes = await services.insights.findings(priority: services.settings.sourcePriority)
                .filter { ($0.kind == .anomaly || $0.kind == .trendChange) && $0.outcome == key }
        }
        .sheet(isPresented: $showPaywall) { PaywallView(highlight: .fullHistoryTrends) }
    }

    private var rangeBinding: Binding<TrendRange> {
        Binding(get: { model.range }, set: { r in
            if r.requiresPro && !entitlements.isEnabled(.fullHistoryTrends) { showPaywall = true } else { model.range = r }
        })
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            let isSum = [.sum, .durationMinutes, .count].contains(metric.dailyStatistic)
            Text(model.range == .day ? (isSum ? "Total" : "Average") : (isSum ? "Daily average" : "Average"))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            let v = model.range == .day && isSum ? model.summary?.total : model.summary?.average
            Text(selected.map { Fmt.value($0.value, metric: metric) } ?? Fmt.value(v, metric: metric))
                .font(.largeTitle.bold().monospacedDigit())
            Text(selected.map { label(for: $0) } ?? model.windowLabel).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var chart: some View {
        if model.loading && model.points.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.points.isEmpty {
            ContentUnavailableView("No data", systemImage: "chart.bar.xaxis",
                                   description: Text("Nothing recorded for this period."))
        } else {
            let unit = calendarUnit
            Chart {
                ForEach(model.points) { p in
                    let x = PlottableValue.value("Date", date(p), unit: unit)
                    if metric.kind == .cumulative || metric.kind == .workout || metric.id == .sleep || metric.kind == .category {
                        BarMark(x: x, y: .value(metric.displayName, p.value))
                            .foregroundStyle(accent.opacity(p.isEstimated ? 0.35 : 0.9))
                            .cornerRadius(3)
                    } else {
                        if let lo = p.min, let hi = p.max, hi > lo {
                            RuleMark(x: x, yStart: .value("Min", lo), yEnd: .value("Max", hi))
                                .foregroundStyle(accent.opacity(0.25))
                                .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round))
                        }
                        PointMark(x: x, y: .value(metric.displayName, p.value))
                            .foregroundStyle(accent.opacity(p.isEstimated ? 0.4 : 1))
                            .symbolSize(30)
                    }
                }
                if showRolling {
                    ForEach(model.rolling) { p in
                        LineMark(x: .value("Date", p.day.date(calendar), unit: .day), y: .value("7-day average", p.value),
                                 series: .value("Series", "avg"))
                            .foregroundStyle(Theme.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .interpolationMethod(.monotone)
                    }
                }
                if let avg = model.summary?.average, model.range != .day {
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                if let s = selected {
                    RuleMark(x: .value("Selected", date(s), unit: unit)).foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartYScale(domain: .automatic(includesZero: metric.kind == .cumulative || metric.kind == .workout))
            .chartXSelection(value: Binding(get: { selected.map(date) }, set: { d in
                selected = d.flatMap { d in model.points.min { abs(date($0).timeIntervalSince(d)) < abs(date($1).timeIntervalSince(d)) } }
            }))
            .accessibilityChartDescriptor(MetricChartDescriptor(title: metric.displayName, unit: metric.unit.symbol,
                                                                points: model.points.map { (label(for: $0), $0.value) }))
        }
    }

    private var calendarUnit: Calendar.Component {
        switch model.range.bucket {
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }

    private func date(_ p: TrendPoint) -> Date { p.day.date(calendar, hour: p.hour) }

    private func label(for p: TrendPoint) -> String {
        let d = date(p)
        switch model.range.bucket {
        case .hour: return d.formatted(date: .omitted, time: .shortened)
        case .day: return Fmt.day(p.day, calendar: calendar)
        case .week: return "Week of \(d.formatted(.dateTime.month(.abbreviated).day()))"
        default: return d.formatted(.dateTime.month(.wide).year())
        }
    }

    private func bestDate(_ b: PersonalBest) -> String {
        let d = b.day.date(calendar)
        switch b.period {
        case .week: return "Week of \(d.formatted(date: .abbreviated, time: .omitted))"
        case .month: return d.formatted(.dateTime.month(.wide).year())
        default: return d.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var about: String {
        var s: String
        switch metric.kind {
        case .cumulative: s = "Totals are deduplicated across devices using your Apple Health source order."
        case .discrete: s = "Each day uses a single source (your preferred one, or the device with the most readings) so devices that measure differently aren't mixed."
        case .category where metric.id == .sleep: s = "Overlapping sleep from several devices is merged; your highest-priority source wins for each part of the night."
        case .workout: s = "Workouts recorded by several apps (e.g. Apple Watch and Garmin) are merged into one."
        default: s = ""
        }
        if model.isPerDayAverage { s += " Bars show the average per day in each period." }
        return s
    }
}

struct ComparisonRow: View {
    let title: String
    let comparison: PeriodComparison
    let metric: MetricType

    var body: some View {
        let dir = comparison.direction(higherIsBetter: metric.higherIsBetter)
        LabeledContent {
            VStack(alignment: .trailing) {
                Text("\(Fmt.value(comparison.current, metric: metric)) vs \(Fmt.value(comparison.previous, metric: metric))")
                    .font(.subheadline.monospacedDigit())
                if let pct = comparison.percentChange {
                    Text("\(pct >= 0 ? "▲" : "▼") \(abs(pct).formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(dir > 0 ? Theme.bluishGreen : (dir < 0 ? Theme.vermillion : .secondary))
                }
            }
        } label: {
            VStack(alignment: .leading) {
                Text(title)
                Text("\(comparison.currentDays) vs \(comparison.previousDays) days with data").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
