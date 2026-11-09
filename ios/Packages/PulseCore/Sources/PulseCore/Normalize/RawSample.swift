import Foundation

/// A sample as it comes out of a data source, before normalization. The shape
/// deliberately mirrors an Apple Health export.xml `<Record>` so the same
/// normalizer (and its fixtures) applies to HealthKit on iOS and to the web
/// importer. A future Health Connect provider maps into this same struct.
public struct RawSample: Sendable, Codable, Hashable {
    /// HealthKit identifier, e.g. "HKQuantityTypeIdentifierStepCount".
    public var typeIdentifier: String
    /// Numeric value (quantity) or category raw value.
    public var value: Double?
    /// Category value as a string (export.xml), e.g. "HKCategoryValueSleepAnalysisAsleepCore".
    public var stringValue: String?
    public var unit: String?
    public var start: Date
    public var end: Date
    public var sourceName: String
    public var sourceBundleId: String
    public var device: DeviceRef?
    public var metadata: [String: String]
    public var uuid: String?

    public init(typeIdentifier: String, value: Double?, stringValue: String? = nil, unit: String?,
                start: Date, end: Date, sourceName: String, sourceBundleId: String = "",
                device: DeviceRef? = nil, metadata: [String: String] = [:], uuid: String? = nil) {
        self.typeIdentifier = typeIdentifier
        self.value = value
        self.stringValue = stringValue
        self.unit = unit
        self.start = start
        self.end = end
        self.sourceName = sourceName
        self.sourceBundleId = sourceBundleId
        self.device = device
        self.metadata = metadata
        self.uuid = uuid
    }
}

/// Parses dates in Apple Health export format: "2024-01-15 07:30:00 -0500".
/// Hand-rolled (no DateFormatter) so it is fast, thread-safe and identical to
/// the web implementation.
public enum HealthDate {
    public static func parse(_ s: String) -> Date? {
        let u = Array(s.utf8)
        // yyyy-MM-dd HH:mm:ss ±hhmm  (25 chars)
        guard u.count >= 19 else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? {
            var v = 0
            for i in from..<(from + len) {
                guard i < u.count, u[i] >= 48, u[i] <= 57 else { return nil }
                v = v * 10 + Int(u[i] - 48)
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2),
              let h = num(11, 2), let mi = num(14, 2), let se = num(17, 2) else { return nil }
        var offsetSeconds = 0
        if u.count >= 25 {
            let signChar = u[20]
            if (signChar == 43 || signChar == 45), let oh = num(21, 2), let om = num(23, 2) {
                offsetSeconds = (oh * 3600 + om * 60) * (signChar == 45 ? -1 : 1)
            }
        }
        let days = DayKey(year: y, month: mo, day: d).julianDay - DayKey(year: 1970, month: 1, day: 1).julianDay
        let secs = Double(days * 86400 + h * 3600 + mi * 60 + se - offsetSeconds)
        return Date(timeIntervalSince1970: secs)
    }
}
