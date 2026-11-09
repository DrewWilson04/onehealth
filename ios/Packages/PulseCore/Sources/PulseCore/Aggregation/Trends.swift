import Foundation

public enum TrendRange: String, CaseIterable, Codable, Sendable, Identifiable {
    case day = "D", week = "W", month = "M", sixMonths = "6M", year = "Y", all = "All"
    public var id: String { rawValue }

    /// Number of days covered (nil = all history).
    public var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 182
        case .year: return 365
        case .all: return nil
        }
    }

    /// Bucket size used for chart points.
    public var bucket: DailyAggregate.Period {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        case .sixMonths: return .week
        case .year: return .month
        case .all: return .month
        }
    }

    /// Free tier only sees ≤ 30 days (Feature.freeTrendDays).
    public var requiresPro: Bool { (days ?? .max) > Feature.freeTrendDays }
}

public struct TrendPoint: Hashable, Codable, Sendable, Identifiable {
    public var day: DayKey
    public var hour: Int?
    public var value: Double
    public var min: Double?
    public var max: Double?
    public var isEstimated: Bool
    public var id: String { "\(day)-\(hour ?? -1)" }
    public init(day: DayKey, hour: Int? = nil, value: Double, min: Double? = nil, max: Double? = nil, isEstimated: Bool = false) {
        self.day = day
        self.hour = hour
        self.value = value
        self.min = min
        self.max = max
        self.isEstimated = isEstimated
    }
}

public struct TrendSummary: Hashable, Codable, Sendable {
    /// Mean per bucket-with-data (for sum metrics: average per day).
    public var average: Double?
    public var total: Double?
    public var min: Double?
    public var max: Double?
    public var daysWithData: Int
}

public struct PeriodComparison: Hashable, Codable, Sendable {
    public var current: Double?
    public var previous: Double?
    public var currentDays: Int
    public var previousDays: Int
    public var delta: Double? {
        guard let c = current, let p = previous else { return nil }
        return c - p
    }
    public var percentChange: Double? {
        guard let c = current, let p = previous, p != 0 else { return nil }
        return (c - p) / abs(p)
    }
    /// +1 better, -1 worse, 0 neutral/unknown, for the metric's direction.
    public func direction(higherIsBetter: Bool?) -> Int {
        guard let d = delta, let hib = higherIsBetter, abs(percentChange ?? 0) >= 0.02 else { return 0 }
        return (d > 0) == hib ? 1 : -1
    }
}

public struct PersonalBest: Hashable, Codable, Sendable {
    public var day: DayKey
    public var value: Double
    public var period: DailyAggregate.Period
}

public enum Trends {
    /// The value plotted/compared for a metric's aggregate.
    public static func value(_ a: DailyAggregate, metric: MetricType) -> Double? {
        a.value(for: metric.dailyStatistic)
    }

    public static func points(_ rows: [DailyAggregate], metric: MetricType) -> [TrendPoint] {
        rows.compactMap { r in
            guard let v = value(r, metric: metric) else { return nil }
            return TrendPoint(day: r.day, hour: r.hour, value: v, min: r.min, max: r.max, isEstimated: r.isEstimated)
        }.sorted { ($0.day, $0.hour ?? 0) < ($1.day, $1.hour ?? 0) }
    }

    /// For rollup rows, sum metrics plot the period total in week view but the
    /// *daily average* in month/year buckets so different-length months are
    /// comparable. Discrete metrics always plot the average.
    public static func rollupPoints(_ rows: [DailyAggregate], metric: MetricType, perDayAverage: Bool) -> [TrendPoint] {
        rows.compactMap { r in
            let v: Double?
            switch metric.dailyStatistic {
            case .sum, .durationMinutes, .count: v = perDayAverage ? r.average : r.sum
            case .average: v = r.average
            case .latest: v = r.latest ?? r.average
            }
            guard let v else { return nil }
            return TrendPoint(day: r.day, value: v, min: r.min, max: r.max, isEstimated: r.isEstimated)
        }.sorted { $0.day < $1.day }
    }

    public static func summary(_ daily: [DailyAggregate], metric: MetricType) -> TrendSummary {
        let vals = daily.compactMap { value($0, metric: metric) }
        guard !vals.isEmpty else { return TrendSummary(average: nil, total: nil, min: nil, max: nil, daysWithData: 0) }
        let total = vals.reduce(0, +)
        let isSum = [.sum, .durationMinutes, .count].contains(metric.dailyStatistic)
        return TrendSummary(average: total / Double(vals.count), total: isSum ? total : nil,
                            min: vals.min(), max: vals.max(), daysWithData: vals.count)
    }

    /// Trailing rolling mean over calendar days. A day's value is emitted only
    /// if at least `minCount` of the `window` days have data (missing days are
    /// skipped, not treated as zero — a watch left on the charger shouldn't
    /// drag the average down).
    public static func rollingAverage(_ points: [TrendPoint], window: Int, minCount: Int? = nil) -> [TrendPoint] {
        let need = minCount ?? Swift.max(1, window / 2)
        let byDay = Dictionary(points.map { ($0.day, $0.value) }, uniquingKeysWith: { a, _ in a })
        guard let first = points.map(\.day).min(), let last = points.map(\.day).max() else { return [] }
        var out: [TrendPoint] = []
        for d in DayKey.range(first, through: last) {
            var sum = 0.0, n = 0
            for k in 0..<window {
                if let v = byDay[d.addingDays(-k)] { sum += v; n += 1 }
            }
            if n >= need && byDay[d] != nil || (n >= need && d == last) {
                out.append(TrendPoint(day: d, value: sum / Double(n)))
            }
        }
        return out
    }

    /// "This week vs last week" (or month / year) using the same number of
    /// elapsed days in both periods, so a Wednesday compares Mon–Wed vs Mon–Wed.
    /// Sum metrics compare the average per day; discrete compare the mean.
    public static func compare(_ daily: [DailyAggregate], metric: MetricType, period: DailyAggregate.Period, today: DayKey) -> PeriodComparison {
        let start: DayKey
        let prevStart: DayKey
        switch period {
        case .week:
            start = today.weekStart
            prevStart = start.addingDays(-7)
        case .month:
            start = today.monthStart
            prevStart = DayKey(year: start.month == 1 ? start.year - 1 : start.year, month: start.month == 1 ? 12 : start.month - 1, day: 1)
        case .year:
            start = today.yearStart
            prevStart = DayKey(year: start.year - 1, month: 1, day: 1)
        default:
            start = today
            prevStart = today.addingDays(-1)
        }
        let elapsed = DayKey.daysBetween(start, today)
        let prevEnd = prevStart.addingDays(elapsed)
        let byDay = Dictionary(daily.filter { $0.period == .day }.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        func mean(_ from: DayKey, _ to: DayKey) -> (Double?, Int) {
            let vals = DayKey.range(from, through: to).compactMap { byDay[$0].flatMap { value($0, metric: metric) } }
            return (vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count), vals.count)
        }
        let (c, cn) = mean(start, today)
        let (p, pn) = mean(prevStart, prevEnd)
        return PeriodComparison(current: c, previous: p, currentDays: cn, previousDays: pn)
    }

    /// Best day / week / month. "Best" follows `higherIsBetter`; neutral
    /// metrics have no personal bests. Estimated values never count.
    public static func personalBests(daily: [DailyAggregate], weekly: [DailyAggregate], monthly: [DailyAggregate],
                                     metric: MetricType) -> [PersonalBest] {
        guard let hib = metric.higherIsBetter else { return [] }
        func best(_ rows: [DailyAggregate], _ p: DailyAggregate.Period, useSum: Bool) -> PersonalBest? {
            let candidates = rows.filter { !$0.isEstimated }.compactMap { r -> (DayKey, Double)? in
                let v: Double? = useSum ? r.sum : (r.average ?? r.latest)
                return v.map { (r.day, $0) }
            }
            let pick = hib ? candidates.max { $0.1 < $1.1 } : candidates.min { $0.1 < $1.1 }
            return pick.map { PersonalBest(day: $0.0, value: $0.1, period: p) }
        }
        let isSum = [.sum, .durationMinutes, .count].contains(metric.dailyStatistic)
        var out: [PersonalBest] = []
        if let d = best(daily, .day, useSum: isSum) { out.append(d) }
        if isSum {
            if let w = best(weekly, .week, useSum: true) { out.append(w) }
            if let m = best(monthly, .month, useSum: true) { out.append(m) }
        }
        return out
    }

    /// Date window for a range ending today (inclusive).
    public static func window(_ range: TrendRange, today: DayKey, earliest: DayKey?) -> (DayKey, DayKey) {
        if let d = range.days { return (today.addingDays(-(d - 1)), today) }
        return (earliest ?? today.addingDays(-365), today)
    }
}
