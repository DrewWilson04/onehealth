import Foundation

/// Ordered source preference. Lower rank wins. The user's explicit order (from
/// Settings → Sources, synced via CloudKit as non-health config) comes first;
/// unlisted sources fall back to the vendor heuristic, then name, so results
/// are deterministic.
public struct SourcePriority: Sendable, Hashable, Codable {
    /// Source keys (`SourceRef.key`) in preferred order.
    public var ordered: [String]

    public init(ordered: [String] = []) { self.ordered = ordered }

    public static let `default` = SourcePriority()

    public func rank(_ source: SourceRef, device: DeviceRef? = nil) -> Int {
        if let i = ordered.firstIndex(of: source.key) { return i }
        if let i = ordered.firstIndex(of: source.name) { return i }
        return 1000 + Vendor.infer(source: source, device: device).defaultRank
    }

    /// Strict ordering helper: (rank, name) so ties are deterministic.
    public func isHigher(_ a: SourceRef, _ aDevice: DeviceRef?, than b: SourceRef, _ bDevice: DeviceRef?) -> Bool {
        let ra = rank(a, device: aDevice), rb = rank(b, device: bDevice)
        if ra != rb { return ra < rb }
        return a.key < b.key
    }

    /// A per-metric preferred source overrides everything for that metric.
    public func preferring(_ key: String?) -> SourcePriority {
        guard let key, !key.isEmpty else { return self }
        return SourcePriority(ordered: [key] + ordered.filter { $0 != key })
    }
}

/// A deduplicated, non-overlapping time segment attributed to one source.
public struct Segment: Sendable, Hashable, Codable {
    public var start: Date
    public var end: Date
    /// For cumulative metrics: the amount in this segment (prorated).
    /// For sleep: the stage code.
    public var value: Double
    public var source: SourceRef
    public var isManual: Bool
    public var isEstimated: Bool

    public init(start: Date, end: Date, value: Double, source: SourceRef, isManual: Bool = false, isEstimated: Bool = false) {
        self.start = start
        self.end = end
        self.value = value
        self.source = source
        self.isManual = isManual
        self.isEstimated = isEstimated
    }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}
