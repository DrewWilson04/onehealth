import Foundation

/// One precomputed value per (metric, day). Weekly/monthly tables use the same
/// shape with `period`. These tables make 10+ years of charts instant.
public struct DailyAggregate: Hashable, Codable, Sendable, Identifiable {
    public enum Period: String, Codable, Sendable { case hour, day, week, month, year }

    public var metric: MetricID
    public var period: Period
    /// Start day of the period (for hour periods: the day; see `hour`).
    public var day: DayKey
    public var hour: Int?
    public var sum: Double?
    public var average: Double?
    public var min: Double?
    public var max: Double?
    public var latest: Double?
    public var count: Int
    /// Source attribution for badges ("via Garmin"): the dominant source key.
    public var primarySource: String?
    public var sourcePolicy: String
    public var isEstimated: Bool
    public var confidence: Confidence?

    public init(metric: MetricID, period: Period = .day, day: DayKey, hour: Int? = nil, sum: Double? = nil, average: Double? = nil,
                min: Double? = nil, max: Double? = nil, latest: Double? = nil, count: Int, primarySource: String? = nil,
                sourcePolicy: String = "merged", isEstimated: Bool = false, confidence: Confidence? = nil) {
        self.metric = metric
        self.period = period
        self.day = day
        self.hour = hour
        self.sum = sum
        self.average = average
        self.min = min
        self.max = max
        self.latest = latest
        self.count = count
        self.primarySource = primarySource
        self.sourcePolicy = sourcePolicy
        self.isEstimated = isEstimated
        self.confidence = confidence
    }

    public var id: String { "\(metric.rawValue)|\(period.rawValue)|\(day)|\(hour ?? -1)|\(sourcePolicy)" }

    /// The value the dashboard displays for this metric's `DailyStatistic`.
    public func value(for stat: DailyStatistic) -> Double? {
        switch stat {
        case .sum, .durationMinutes: return sum
        case .average: return average
        case .latest: return latest ?? average
        case .count: return Double(count)
        }
    }
}
