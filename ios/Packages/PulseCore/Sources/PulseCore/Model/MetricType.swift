import Foundation

public enum DashboardSection: String, Codable, Sendable, CaseIterable, Identifiable {
    case activity, sleep, heart, body
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .activity: return "Activity & Workouts"
        case .sleep: return "Sleep & Recovery"
        case .heart: return "Heart & Vitals"
        case .body: return "Body & Nutrition"
        }
    }
}

/// How a metric's samples combine.
public enum MetricKind: String, Codable, Sendable {
    /// Additive over time (steps, energy, distance, nutrients). Must be deduped
    /// with source priority, never naively summed across sources.
    case cumulative
    /// Point measurements (HR, HRV, weight). Averaged per day from one source.
    case discrete
    /// Category samples with duration (sleep stages, mindful sessions, events).
    case category
    /// Workouts. Value = duration in minutes; details in metadata.
    case workout
    /// ECG recordings (summary only). Value = average HR.
    case ecg
}

/// Which statistic the dashboard shows for a day.
public enum DailyStatistic: String, Codable, Sendable {
    case sum, average, latest, durationMinutes, count
}

public struct MetricType: Hashable, Codable, Sendable, Identifiable {
    public var id: MetricID
    public var displayName: String
    public var unit: MetricUnit
    public var kind: MetricKind
    public var dailyStatistic: DailyStatistic
    public var section: DashboardSection
    /// HealthKit type identifier (also used verbatim as `type` in export.xml).
    public var healthKitIdentifier: String?
    /// High-volume types are stored as aggregates only (no raw rows) to keep
    /// 10+ years of history fast. See /docs/schema.md.
    public var isHighVolume: Bool
    /// Whether the app may write this type back to HealthKit (manual entry).
    public var isWritable: Bool
    /// Higher-is-better for trends / personal bests (nil = neutral).
    public var higherIsBetter: Bool?
    /// SF Symbol name for UI.
    public var symbol: String

    public init(id: MetricID, displayName: String, unit: MetricUnit, kind: MetricKind,
                dailyStatistic: DailyStatistic, section: DashboardSection,
                healthKitIdentifier: String?, isHighVolume: Bool = false,
                isWritable: Bool = false, higherIsBetter: Bool? = nil, symbol: String) {
        self.id = id
        self.displayName = displayName
        self.unit = unit
        self.kind = kind
        self.dailyStatistic = dailyStatistic
        self.section = section
        self.healthKitIdentifier = healthKitIdentifier
        self.isHighVolume = isHighVolume
        self.isWritable = isWritable
        self.higherIsBetter = higherIsBetter
        self.symbol = symbol
    }
}
