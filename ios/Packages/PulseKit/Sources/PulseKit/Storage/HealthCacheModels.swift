import Foundation
import SwiftData
import PulseCore

// Local-only health cache. These models live in a SwiftData store that is
// explicitly configured with `cloudKitDatabase: .none` (see LocalStore).
// App Review guideline 5.1.3(ii): personal health information must NOT be
// stored in iCloud — never add these models to the CloudKit-backed settings
// container.

@Model
public final class SampleRecord {
    #Index<SampleRecord>([\.type, \.start], [\.id])

    @Attribute(.unique) public var id: String
    public var type: String
    public var value: Double
    public var unit: String
    public var start: Date
    public var end: Date
    public var sourceBundleId: String
    public var sourceName: String
    public var deviceName: String?
    public var deviceModel: String?
    public var deviceManufacturer: String?
    public var isManual: Bool
    public var isEstimated: Bool
    public var confidence: String?
    public var metadataJSON: Data?

    public init(_ s: Sample) {
        id = s.id
        type = s.type.rawValue
        value = s.value
        unit = s.unit.rawValue
        start = s.start
        end = s.end
        sourceBundleId = s.source.bundleId
        sourceName = s.source.name
        deviceName = s.device?.name
        deviceModel = s.device?.model
        deviceManufacturer = s.device?.manufacturer
        isManual = s.isManual
        isEstimated = s.isEstimated
        confidence = s.confidence?.rawValue
        metadataJSON = s.metadata.flatMap { try? JSONEncoder().encode($0) }
    }

    public var sample: Sample {
        Sample(id: id, type: MetricID(type), value: value, unit: MetricUnit(rawValue: unit) ?? .count,
               start: start, end: end, source: SourceRef(bundleId: sourceBundleId, name: sourceName),
               device: (deviceName ?? deviceModel ?? deviceManufacturer) == nil ? nil
                   : DeviceRef(name: deviceName, model: deviceModel, manufacturer: deviceManufacturer),
               isManual: isManual, isEstimated: isEstimated, confidence: confidence.flatMap(Confidence.init(rawValue:)),
               metadata: metadataJSON.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) })
    }
}

/// Precomputed hourly/daily/weekly/monthly aggregate (see /docs/schema.md).
@Model
public final class AggregateRecord {
    #Index<AggregateRecord>([\.metric, \.period, \.dayIndex], [\.key])

    @Attribute(.unique) public var key: String
    public var metric: String
    public var period: String
    public var day: String
    /// Julian day number — fast range queries without string compares.
    public var dayIndex: Int
    public var hour: Int
    public var sum: Double?
    public var average: Double?
    public var minimum: Double?
    public var maximum: Double?
    public var latest: Double?
    public var count: Int
    public var primarySource: String?
    public var sourcePolicy: String
    public var isEstimated: Bool
    public var confidence: String?

    public init(_ a: DailyAggregate) {
        key = AggregateRecord.key(a)
        metric = a.metric.rawValue
        period = a.period.rawValue
        day = a.day.description
        dayIndex = a.day.julianDay
        hour = a.hour ?? -1
        sum = a.sum
        average = a.average
        minimum = a.min
        maximum = a.max
        latest = a.latest
        count = a.count
        primarySource = a.primarySource
        sourcePolicy = a.sourcePolicy
        isEstimated = a.isEstimated
        confidence = a.confidence?.rawValue
    }

    /// One row per (metric, period, day, hour). The row always reflects the
    /// *effective* source policy (user preference or merged); changing a
    /// preferred source recomputes the metric.
    public static func key(_ a: DailyAggregate) -> String {
        "\(a.metric.rawValue)|\(a.period.rawValue)|\(a.day)|\(a.hour ?? -1)"
    }

    public func update(from a: DailyAggregate) {
        sum = a.sum
        average = a.average
        minimum = a.min
        maximum = a.max
        latest = a.latest
        count = a.count
        primarySource = a.primarySource
        isEstimated = a.isEstimated
        confidence = a.confidence?.rawValue
    }

    public var aggregate: DailyAggregate {
        DailyAggregate(metric: MetricID(metric), period: DailyAggregate.Period(rawValue: period) ?? .day,
                       day: DayKey(julianDay: dayIndex), hour: hour < 0 ? nil : hour, sum: sum, average: average,
                       min: minimum, max: maximum, latest: latest, count: count, primarySource: primarySource,
                       sourcePolicy: sourcePolicy, isEstimated: isEstimated, confidence: confidence.flatMap(Confidence.init(rawValue:)))
    }
}

/// Cached derived score per day (Readiness, Strain, Energy, Sleep Score...).
@Model
public final class ScoreRecord {
    #Index<ScoreRecord>([\.kind, \.dayIndex])

    @Attribute(.unique) public var key: String
    public var kind: String
    public var dayIndex: Int
    public var payload: Data

    public init(kind: String, day: DayKey, payload: Data) {
        key = "\(kind)|\(day)"
        self.kind = kind
        dayIndex = day.julianDay
        self.payload = payload
    }
}

/// Per-metric ingestion state: HealthKit anchor + backfill checkpoint.
@Model
public final class SyncStateRecord {
    @Attribute(.unique) public var metric: String
    public var anchorData: Data?
    /// Oldest date fully ingested so far (backfill walks backwards from now).
    public var backfilledFrom: Date?
    public var backfillComplete: Bool
    public var lastSync: Date?

    public init(metric: String) {
        self.metric = metric
        backfillComplete = false
    }
}

/// User-defined metric with no HealthKit type. Local-only, never synced.
@Model
public final class CustomMetricRecord {
    @Attribute(.unique) public var id: String
    public var name: String
    public var unitLabel: String
    public var symbol: String
    public var aggregation: String  // "sum" | "average" | "latest"
    public var createdAt: Date

    public init(id: String = UUID().uuidString, name: String, unitLabel: String, symbol: String = "star", aggregation: String = "sum") {
        self.id = id
        self.name = name
        self.unitLabel = unitLabel
        self.symbol = symbol
        self.aggregation = aggregation
        createdAt = Date()
    }
}

/// Recent-foods index for quick re-logging. The nutrition values themselves
/// live in HealthKit (as an HKCorrelation); this local row only powers the
/// "recent foods" list and is never synced to iCloud.
@Model
public final class FoodLogRecord {
    @Attribute(.unique) public var id: String
    /// HealthKit correlation UUID, when written.
    public var healthKitId: String?
    public var name: String
    public var date: Date
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var meal: String

    public init(id: String = UUID().uuidString, healthKitId: String?, name: String, date: Date,
                kcal: Double, protein: Double, carbs: Double, fat: Double, meal: String) {
        self.id = id
        self.healthKitId = healthKitId
        self.name = name
        self.date = date
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.meal = meal
    }
}
