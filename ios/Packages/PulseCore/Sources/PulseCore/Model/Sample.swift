import Foundation

public enum Confidence: String, Codable, Sendable, Comparable {
    case low, medium, high
    private var order: Int { self == .low ? 0 : self == .medium ? 1 : 2 }
    public static func < (a: Confidence, b: Confidence) -> Bool { a.order < b.order }
}

/// The normalized, platform-neutral sample. See /docs/schema.md.
public struct Sample: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var type: MetricID
    public var value: Double
    public var unit: MetricUnit
    public var start: Date
    public var end: Date
    public var source: SourceRef
    public var device: DeviceRef?
    public var isManual: Bool
    public var isEstimated: Bool
    public var confidence: Confidence?
    public var metadata: [String: String]?

    public init(id: String, type: MetricID, value: Double, unit: MetricUnit, start: Date, end: Date,
                source: SourceRef, device: DeviceRef? = nil, isManual: Bool = false, isEstimated: Bool = false,
                confidence: Confidence? = nil, metadata: [String: String]? = nil) {
        self.id = id
        self.type = type
        self.value = value
        self.unit = unit
        self.start = start
        self.end = max(start, end)
        self.source = source
        self.device = device
        self.isManual = isManual
        self.isEstimated = isEstimated
        self.confidence = confidence
        self.metadata = metadata
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var vendor: Vendor { Vendor.infer(source: source, device: device) }
    /// True when this sample may be used for competitive challenge scoring.
    public var isCompetitionEligible: Bool { !isManual && !isEstimated }
}

/// Sleep stage codes. Raw values match `HKCategoryValueSleepAnalysis`.
public enum SleepStage: Int, Codable, Sendable, CaseIterable {
    case inBed = 0
    case asleepUnspecified = 1
    case awake = 2
    case core = 3
    case deep = 4
    case rem = 5

    public var isAsleep: Bool { self == .asleepUnspecified || self == .core || self == .deep || self == .rem }
    public var label: String {
        switch self {
        case .inBed: return "In Bed"
        case .asleepUnspecified: return "Asleep"
        case .awake: return "Awake"
        case .core: return "Core"
        case .deep: return "Deep"
        case .rem: return "REM"
        }
    }

    /// Maps export.xml string values (e.g. `HKCategoryValueSleepAnalysisAsleepCore`).
    public init?(exportValue: String) {
        switch exportValue {
        case "HKCategoryValueSleepAnalysisInBed": self = .inBed
        case "HKCategoryValueSleepAnalysisAsleep", "HKCategoryValueSleepAnalysisAsleepUnspecified": self = .asleepUnspecified
        case "HKCategoryValueSleepAnalysisAwake": self = .awake
        case "HKCategoryValueSleepAnalysisAsleepCore": self = .core
        case "HKCategoryValueSleepAnalysisAsleepDeep": self = .deep
        case "HKCategoryValueSleepAnalysisAsleepREM": self = .rem
        default: return nil
        }
    }
}

/// Typed view over a workout `Sample` (value = minutes, details in metadata).
public struct WorkoutInfo: Sendable, Hashable {
    public static let activityTypeKey = "activityType"
    public static let energyKey = "energyKcal"
    public static let distanceKey = "distanceM"
    public static let avgHRKey = "avgHR"
    public static let hasRouteKey = "hasRoute"
    public static let setsKey = "PulseBoardSets"
    public static let mergedFromKey = "mergedFrom"

    public let sample: Sample
    public init?(_ sample: Sample) {
        guard sample.type == .workout else { return nil }
        self.sample = sample
    }
    public var durationMinutes: Double { sample.value }
    public var activityType: String { sample.metadata?[Self.activityTypeKey] ?? "other" }
    public var energyKcal: Double? { sample.metadata?[Self.energyKey].flatMap(Double.init) }
    public var distanceMeters: Double? { sample.metadata?[Self.distanceKey].flatMap(Double.init) }
    public var averageHeartRate: Double? { sample.metadata?[Self.avgHRKey].flatMap(Double.init) }
    public var hasRoute: Bool { sample.metadata?[Self.hasRouteKey] == "1" }
}
