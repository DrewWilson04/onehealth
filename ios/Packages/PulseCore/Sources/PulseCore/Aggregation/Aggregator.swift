import Foundation

/// Builds daily aggregates from normalized samples, applying the dedup rules
/// for each metric kind, plus week/month/year rollups. HealthKit statistics
/// produce equivalent daily rows on iOS for quantity types; this is used on
/// iOS for sleep/workouts/events/custom metrics and for everything on web.
public enum Aggregator {
    public struct Options: Sendable {
        public var priority: SourcePriority
        public var preferredSource: [MetricID: String]
        public var calendar: Calendar
        public init(priority: SourcePriority = .default, preferredSource: [MetricID: String] = [:], calendar: Calendar = .pulse()) {
            self.priority = priority
            self.preferredSource = preferredSource
            self.calendar = calendar
        }
    }

    public static func daily(_ metric: MetricType, samples: [Sample], options: Options) -> [DailyAggregate] {
        let cal = options.calendar
        let priority = options.priority.preferring(options.preferredSource[metric.id])
        let policy = options.preferredSource[metric.id].map { "pref:\($0)" } ?? "merged"
        let ofType = samples.filter { $0.type == metric.id }
        guard !ofType.isEmpty else { return [] }

        switch metric.kind {
        case .cumulative:
            let segs = CumulativeDeduper.dedupe(ofType, priority: priority)
            var byDay: [DayKey: (sum: Double, est: Bool, src: [String: Double])] = [:]
            let bins = CumulativeDeduper.bin(segs, binStart: { cal.startOfDay(for: $0) },
                                             binEnd: { cal.date(byAdding: .day, value: 1, to: $0)! })
            for (d, v) in bins { byDay[DayKey(d, calendar: cal), default: (0, false, [:])].sum += v }
            for s in segs {
                let k = DayKey(s.start, calendar: cal)
                byDay[k, default: (0, false, [:])].src[s.source.key, default: 0] += s.value
                if s.isEstimated { byDay[k]?.est = true }
            }
            return byDay.map { day, v in
                DailyAggregate(metric: metric.id, day: day, sum: v.sum, count: 1,
                               primarySource: v.src.max { $0.value < $1.value }?.key, sourcePolicy: policy, isEstimated: v.est)
            }.sorted { $0.day < $1.day }

        case .discrete, .ecg:
            let grouped = Dictionary(grouping: ofType) { DayKey($0.start, calendar: cal) }
            return grouped.compactMap { day, list -> DailyAggregate? in
                let chosen = DiscreteSourceSelector.select(list, preferredSourceKey: options.preferredSource[metric.id], priority: priority)
                guard !chosen.isEmpty else { return nil }
                let vals = chosen.map(\.value)
                let latest = chosen.max { $0.end < $1.end }!.value
                return DailyAggregate(metric: metric.id, day: day, sum: vals.reduce(0, +), average: vals.reduce(0, +) / Double(vals.count),
                                      min: vals.min(), max: vals.max(), latest: latest, count: vals.count,
                                      primarySource: chosen[0].source.key, sourcePolicy: policy,
                                      isEstimated: chosen.contains(where: \.isEstimated))
            }.sorted { $0.day < $1.day }

        case .category:
            if metric.id == .sleep {
                return SleepMerger.nights(ofType, priority: priority, calendar: cal).map { n in
                    DailyAggregate(metric: .sleep, day: n.day, sum: n.asleepMinutes, average: n.efficiency.map { $0 * 100 },
                                   min: nil, max: n.inBedMinutes, latest: nil, count: 1,
                                   primarySource: n.primarySource.key, sourcePolicy: policy, isEstimated: n.isEstimated)
                }
            }
            // Mindful sessions → minutes; events/stand hours → counts. Overlaps
            // across sources are merged by sweeping (same as sleep).
            let segs = SleepMerger.sweep(ofType, priority: priority)
            var byDay: [DayKey: (min: Double, count: Int)] = [:]
            if metric.id == .standHour {
                // Stand hour: value 0 = stood. One per hour; dedup by hour slot.
                var slots = Set<String>()
                for s in ofType where s.value == 0 {
                    let d = DayKey(s.start, calendar: cal)
                    let h = cal.component(.hour, from: s.start)
                    if slots.insert("\(d)-\(h)").inserted { byDay[d, default: (0, 0)].count += 1 }
                }
            } else {
                for s in segs {
                    let d = DayKey(s.start, calendar: cal)
                    byDay[d, default: (0, 0)].min += s.duration / 60
                    byDay[d, default: (0, 0)].count += 1
                }
                if segs.isEmpty {
                    for s in ofType { byDay[DayKey(s.start, calendar: cal), default: (0, 0)].count += 1 }
                }
            }
            return byDay.map { day, v in
                DailyAggregate(metric: metric.id, day: day, sum: metric.dailyStatistic == .count ? Double(v.count) : v.min,
                               count: v.count, sourcePolicy: policy)
            }.sorted { $0.day < $1.day }

        case .workout:
            let merged = WorkoutMerger.merge(ofType, priority: priority)
            let grouped = Dictionary(grouping: merged) { DayKey($0.start, calendar: cal) }
            return grouped.map { day, list in
                let energy = list.compactMap { WorkoutInfo($0)?.energyKcal }.reduce(0, +)
                return DailyAggregate(metric: .workout, day: day, sum: list.reduce(0) { $0 + $1.value },
                                      average: energy > 0 ? energy : nil, count: list.count,
                                      primarySource: list.first?.source.key, sourcePolicy: policy,
                                      isEstimated: list.contains(where: \.isEstimated))
            }.sorted { $0.day < $1.day }
        }
    }

    /// Rolls daily rows up into weeks (ISO, Monday start), months or years.
    /// - sum / duration metrics: period total (and `average` = mean per day with data)
    /// - average metrics: mean of daily averages; min/max over the period
    /// - latest metrics: last daily value in the period
    public static func rollup(_ daily: [DailyAggregate], metric: MetricType, to period: DailyAggregate.Period) -> [DailyAggregate] {
        precondition(period == .week || period == .month || period == .year)
        func key(_ d: DayKey) -> DayKey {
            switch period {
            case .week: return d.weekStart
            case .month: return d.monthStart
            default: return d.yearStart
            }
        }
        let groups = Dictionary(grouping: daily.filter { $0.period == .day }) { key($0.day) }
        return groups.map { start, rows in
            let sorted = rows.sorted { $0.day < $1.day }
            let est = rows.contains(where: \.isEstimated)
            let src = Dictionary(grouping: rows.compactMap(\.primarySource), by: { $0 }).max { $0.value.count < $1.value.count }?.key
            switch metric.dailyStatistic {
            case .sum, .durationMinutes, .count:
                let vals = sorted.compactMap { $0.value(for: metric.dailyStatistic) }
                let total = vals.reduce(0, +)
                return DailyAggregate(metric: metric.id, period: period, day: start, sum: total,
                                      average: vals.isEmpty ? nil : total / Double(vals.count),
                                      min: vals.min(), max: vals.max(), latest: vals.last, count: vals.count,
                                      primarySource: src, sourcePolicy: rows[0].sourcePolicy, isEstimated: est)
            case .average, .latest:
                let avgs = sorted.compactMap { $0.average ?? $0.latest }
                return DailyAggregate(metric: metric.id, period: period, day: start,
                                      average: avgs.isEmpty ? nil : avgs.reduce(0, +) / Double(avgs.count),
                                      min: sorted.compactMap { $0.min ?? $0.average }.min(),
                                      max: sorted.compactMap { $0.max ?? $0.average }.max(),
                                      latest: sorted.last.flatMap { $0.latest ?? $0.average }, count: avgs.count,
                                      primarySource: src, sourcePolicy: rows[0].sourcePolicy, isEstimated: est)
            }
        }.sorted { $0.day < $1.day }
    }
}
