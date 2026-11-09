import Foundation

/// Access state per metric. HealthKit never reveals whether *read* access was
/// denied (privacy by design), so read state is `.unknown` until we see data;
/// write state is exact.
public enum AccessState: String, Codable, Sendable {
    case notRequested, granted, denied, unknown, unavailable
}

public struct MetricAccess: Codable, Sendable, Hashable {
    public var metric: MetricID
    public var read: AccessState
    public var write: AccessState
    public var hasData: Bool
    public init(metric: MetricID, read: AccessState, write: AccessState, hasData: Bool) {
        self.metric = metric
        self.read = read
        self.write = write
        self.hasData = hasData
    }
}

public struct AccessSummary: Codable, Sendable {
    public var metrics: [MetricAccess]
    public init(metrics: [MetricAccess]) { self.metrics = metrics }

    /// Sections where at least one core metric has no data (likely denied or
    /// no device records it). Used for the "limited" banners.
    public func limitedSections(coreMetrics: [DashboardSection: [MetricID]] = AccessSummary.coreMetrics) -> [DashboardSection: [MetricID]] {
        var out: [DashboardSection: [MetricID]] = [:]
        let byID = Dictionary(uniqueKeysWithValues: metrics.map { ($0.metric, $0) })
        for (section, ids) in coreMetrics {
            let missing = ids.filter { byID[$0].map { !$0.hasData || $0.read == .denied } ?? true }
            if !missing.isEmpty { out[section] = missing }
        }
        return out
    }

    public static let coreMetrics: [DashboardSection: [MetricID]] = [
        .activity: [.steps, .activeEnergy, .workout],
        .sleep: [.sleep],
        .heart: [.heartRate, .restingHeartRate, .hrv],
        .body: [.bodyMass, .dietaryEnergy],
    ]
}

/// Describes a change from a provider (new/deleted samples) so the local
/// cache can mark days dirty and recompute only what changed.
public struct DataChange: Sendable {
    public var metric: MetricID
    public var added: [Sample]
    public var deletedIDs: [String]
    public var affectedDays: Set<DayKey>
    public init(metric: MetricID, added: [Sample], deletedIDs: [String], affectedDays: Set<DayKey>) {
        self.metric = metric
        self.added = added
        self.deletedIDs = deletedIDs
        self.affectedDays = affectedDays
    }
}

/// How cumulative/discrete values are combined across sources for a metric.
public enum SourcePolicy: Codable, Sendable, Hashable {
    /// Use the platform's merged statistics (HealthKit source priority).
    case merged
    /// Use only this source key (falls back to merged when it has no data that day).
    case preferred(String)

    public var key: String {
        switch self {
        case .merged: return "merged"
        case .preferred(let s): return "pref:\(s)"
        }
    }
}

/// A source of health data. Apple Health (HealthKit) is the only provider in
/// this phase. Future providers (Health Connect on Android, direct Fitbit /
/// WHOOP / Garmin / Oura APIs) implement the same protocol.
///
/// TODO(provider-connectors): direct API providers need OAuth (auth service),
/// a server-side token exchange, and webhooks → they belong to the server
/// phase. Keep them behind this protocol so UI code is unchanged.
public protocol DataProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func isAvailable() -> Bool
    func supportedMetrics() -> [MetricID]
    func requestAuthorization(read: [MetricID], write: [MetricID]) async throws
    func accessSummary() async -> AccessSummary
    /// Normalized samples in `interval` (deduplication is the caller's job,
    /// except where the provider can do it natively — see `dailyAggregates`).
    func samples(of metric: MetricID, in interval: DateInterval) async throws -> [Sample]
    /// Per-day aggregates computed by the provider (HealthKit statistics apply
    /// source priority for cumulative types).
    func dailyAggregates(of metric: MetricID, in interval: DateInterval, policy: SourcePolicy, calendar: Calendar) async throws -> [DailyAggregate]
    /// Sources that have written this metric.
    func sources(for metric: MetricID) async throws -> [SourceRef]
}
