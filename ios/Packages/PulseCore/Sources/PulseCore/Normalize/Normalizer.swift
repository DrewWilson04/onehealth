import Foundation

/// Why a raw sample was dropped during normalization (surfaced in import logs).
public enum NormalizationIssue: String, Sendable, Codable {
    case unknownType, unknownUnit, missingValue, unknownCategoryValue, invalidInterval
}

public struct NormalizationResult: Sendable {
    public var sample: Sample?
    public var issue: NormalizationIssue?
}

/// Converts `RawSample`s into canonical `Sample`s. Rules (see /docs/schema.md):
/// - type mapped via `MetricRegistry` (unknown types are skipped)
/// - value converted to the metric's canonical unit
/// - percentages: HealthKit fractions (0–1) → 0–100
/// - category values mapped to stable integer codes
/// - `isManual` when metadata HKWasUserEntered == 1 or the source is our app
/// - stable id: HealthKit UUID when known, else a deterministic hash
public struct Normalizer: Sendable {
    public var ownBundleIdPrefix: String

    public init(ownBundleIdPrefix: String = AppBrandName.bundlePrefixHint) {
        self.ownBundleIdPrefix = ownBundleIdPrefix
    }

    public func normalize(_ raw: RawSample) -> NormalizationResult {
        guard let metric = MetricRegistry.type(healthKitIdentifier: raw.typeIdentifier) else {
            return .init(sample: nil, issue: .unknownType)
        }
        guard raw.end >= raw.start else { return .init(sample: nil, issue: .invalidInterval) }

        let value: Double
        switch metric.kind {
        case .cumulative, .discrete:
            guard let v = raw.value, v.isFinite else { return .init(sample: nil, issue: .missingValue) }
            guard let u = raw.unit, let converted = UnitConverter.convert(v, from: u, to: metric.unit) else {
                return .init(sample: nil, issue: .unknownUnit)
            }
            value = converted
        case .category:
            if metric.id == .sleep {
                if let s = raw.stringValue, let stage = SleepStage(exportValue: s) {
                    value = Double(stage.rawValue)
                } else if let v = raw.value, let stage = SleepStage(rawValue: Int(v)) {
                    value = Double(stage.rawValue)
                } else {
                    return .init(sample: nil, issue: .unknownCategoryValue)
                }
            } else {
                // Events / stand hours / mindful: keep the category raw value if
                // numeric, else 0. Stand hour: 0 = stood, 1 = idle.
                if let v = raw.value { value = v }
                else if let s = raw.stringValue { value = Self.categoryCode(s) }
                else { value = 0 }
            }
        case .workout:
            // Workouts are normalized by `normalizeWorkout`; a RawSample here
            // carries the duration in minutes.
            guard let v = raw.value else { return .init(sample: nil, issue: .missingValue) }
            value = UnitConverter.convert(v, from: raw.unit ?? "min", to: .minute) ?? v
        case .ecg:
            value = raw.value ?? 0
        }

        let isManual = raw.metadata["HKWasUserEntered"] == "1"
            || (!ownBundleIdPrefix.isEmpty && raw.sourceBundleId.hasPrefix(ownBundleIdPrefix))
        let source = SourceRef(bundleId: raw.sourceBundleId, name: raw.sourceName)
        let id = raw.uuid ?? Self.stableId(raw)
        let meta = raw.metadata.isEmpty ? nil : raw.metadata
        let s = Sample(id: id, type: metric.id, value: value, unit: metric.unit, start: raw.start, end: raw.end,
                       source: source, device: raw.device, isManual: isManual, isEstimated: false,
                       confidence: nil, metadata: meta)
        return .init(sample: s, issue: nil)
    }

    /// Workouts from export.xml `<Workout>` or HKWorkout.
    public func normalizeWorkout(activityType: String, start: Date, end: Date, durationMinutes: Double?,
                                 energyKcal: Double?, distanceMeters: Double?, averageHeartRate: Double? = nil,
                                 hasRoute: Bool, sourceName: String, sourceBundleId: String, device: DeviceRef?,
                                 metadata: [String: String], uuid: String?) -> Sample {
        var meta = metadata
        meta[WorkoutInfo.activityTypeKey] = Self.shortActivityName(activityType)
        if let e = energyKcal { meta[WorkoutInfo.energyKey] = String(format: "%.1f", e) }
        if let d = distanceMeters { meta[WorkoutInfo.distanceKey] = String(format: "%.1f", d) }
        if let hr = averageHeartRate { meta[WorkoutInfo.avgHRKey] = String(format: "%.1f", hr) }
        if hasRoute { meta[WorkoutInfo.hasRouteKey] = "1" }
        let minutes = durationMinutes ?? end.timeIntervalSince(start) / 60
        let isManual = metadata["HKWasUserEntered"] == "1"
            || (!ownBundleIdPrefix.isEmpty && sourceBundleId.hasPrefix(ownBundleIdPrefix))
        let raw = RawSample(typeIdentifier: "HKWorkoutTypeIdentifier", value: minutes, unit: "min", start: start, end: end,
                            sourceName: sourceName, sourceBundleId: sourceBundleId, device: device, metadata: meta, uuid: uuid)
        return Sample(id: uuid ?? Self.stableId(raw), type: .workout, value: minutes, unit: .minute, start: start, end: end,
                      source: SourceRef(bundleId: sourceBundleId, name: sourceName), device: device,
                      isManual: isManual, metadata: meta)
    }

    /// "HKWorkoutActivityTypeRunning" → "running".
    public static func shortActivityName(_ s: String) -> String {
        let prefix = "HKWorkoutActivityType"
        var name = s.hasPrefix(prefix) ? String(s.dropFirst(prefix.count)) : s
        if let f = name.first { name = f.lowercased() + name.dropFirst() }
        return name
    }

    static func categoryCode(_ s: String) -> Double {
        switch s {
        case "HKCategoryValueAppleStandHourStood": return 0
        case "HKCategoryValueAppleStandHourIdle": return 1
        default: return 0
        }
    }

    /// Deterministic id for samples without a UUID (export.xml has none):
    /// FNV-1a 64 over type|start|end|value|source. Same algorithm on web.
    public static func stableId(_ r: RawSample) -> String {
        let v = r.value.map { String(format: "%.6f", $0) } ?? (r.stringValue ?? "")
        let key = "\(r.typeIdentifier)|\(Int64(r.start.timeIntervalSince1970))|\(Int64(r.end.timeIntervalSince1970))|\(v)|\(r.sourceBundleId.isEmpty ? r.sourceName : r.sourceBundleId)"
        return "x" + fnv1a64Hex(key)
    }

    public static func fnv1a64Hex(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
