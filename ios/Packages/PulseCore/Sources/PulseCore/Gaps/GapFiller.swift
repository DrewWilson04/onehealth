import Foundation

public struct FilledValue: Codable, Sendable, Hashable {
    public var value: Double
    public var isEstimated: Bool
    public var confidence: Confidence?
}

/// Fills *short* gaps only, using baseline-weighted values, and marks them
/// estimated with a confidence level. Long gaps stay empty ("not enough
/// data"). Filled values are for display and personal scores only — they
/// are NEVER used in challenge scoring.
public enum GapFiller {
    public static let maxDailyGap = 2
    public static let maxIntradayGap: TimeInterval = 3 * 3600

    /// Daily series: for each missing day `d` within `maxDailyGap` days after
    /// the last measured day, value = w·last + (1−w)·baseline where
    /// w = 0.5 for the first missing day, 0.25 for the second.
    /// Confidence: high if gap = 1 and baseline CV < 0.10; medium if CV < 0.25;
    /// otherwise low.
    public static func fillDaily(_ measured: [DayKey: Double], from: DayKey, through: DayKey,
                                 maxGap: Int = maxDailyGap) -> [DayKey: FilledValue] {
        var out: [DayKey: FilledValue] = [:]
        for (k, v) in measured where k >= from && k <= through { out[k] = FilledValue(value: v, isEstimated: false, confidence: nil) }
        guard from <= through else { return out }
        var day = from
        while day <= through {
            if measured[day] == nil {
                // Find last measured day before `day`.
                var back = 1
                var last: Double?
                while back <= maxGap {
                    if let v = measured[day.addingDays(-back)] { last = v; break }
                    back += 1
                }
                if let last, let base = Baseline.compute(measured, before: day, window: Baseline.windowDays, minDays: 7) {
                    let w = back == 1 ? 0.5 : 0.25
                    let value = w * last + (1 - w) * base.mean
                    let cv = base.mean != 0 ? base.sd / abs(base.mean) : 1
                    let conf: Confidence = (back == 1 && cv < 0.10) ? .high : (cv < 0.25 ? .medium : .low)
                    out[day] = FilledValue(value: value, isEstimated: true, confidence: back == 1 ? conf : min(conf, .medium))
                }
            }
            day = day.addingDays(1)
        }
        return out
    }

    /// Intraday series (e.g. heart rate): linearly interpolates gaps no longer
    /// than `maxGap`, at `step` resolution. Returned points are flagged.
    public static func fillSeries(_ points: [(Date, Double)], step: TimeInterval = 900, maxGap: TimeInterval = maxIntradayGap) -> [(Date, Double, Bool)] {
        let sorted = points.sorted { $0.0 < $1.0 }
        var out: [(Date, Double, Bool)] = []
        for (i, p) in sorted.enumerated() {
            out.append((p.0, p.1, false))
            guard i + 1 < sorted.count else { continue }
            let n = sorted[i + 1]
            let gap = n.0.timeIntervalSince(p.0)
            guard gap > step * 1.5, gap <= maxGap else { continue }
            var t = p.0.addingTimeInterval(step)
            while t < n.0.addingTimeInterval(-step / 2) {
                let f = t.timeIntervalSince(p.0) / gap
                out.append((t, p.1 + (n.1 - p.1) * f, true))
                t = t.addingTimeInterval(step)
            }
        }
        return out
    }
}
