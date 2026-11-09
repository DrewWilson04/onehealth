import Foundation

/// Deduplicates cumulative samples (steps, energy, distance, nutrients) across
/// sources the same way Apple Health's statistics do: for every instant, only
/// the highest-priority source that has a sample covering that instant counts.
/// Each sample's value is assumed to be spread uniformly over its duration.
///
/// On iOS we prefer `HKStatisticsCollectionQuery` (which applies the user's
/// Health app source order); this implementation is used on web (export.xml
/// has no priority applied), for local-only data, and as the tested reference.
public enum CumulativeDeduper {
    /// Zero-length samples are treated as lasting this long so they still
    /// participate in overlap resolution.
    static let instantDuration: TimeInterval = 1

    public static func dedupe(_ samples: [Sample], priority: SourcePriority) -> [Segment] {
        guard !samples.isEmpty else { return [] }

        struct Item {
            let start: TimeInterval
            let end: TimeInterval
            let rate: Double
            let rank: Int
            let sourceKey: String
            let sample: Sample
        }
        let items: [Item] = samples.map { s in
            let st = s.start.timeIntervalSince1970
            var en = s.end.timeIntervalSince1970
            if en <= st { en = st + instantDuration }
            return Item(start: st, end: en, rate: s.value / (en - st), rank: priority.rank(s.source, device: s.device),
                        sourceKey: s.source.key, sample: s)
        }

        var bounds = Set<TimeInterval>()
        for i in items { bounds.insert(i.start); bounds.insert(i.end) }
        let sortedBounds = bounds.sorted()
        let byStart = items.sorted { $0.start < $1.start }

        var segments: [Segment] = []
        var active: [Item] = []
        var next = 0
        for bi in 0..<(sortedBounds.count - 1) {
            let a = sortedBounds[bi], b = sortedBounds[bi + 1]
            active.removeAll { $0.end <= a }
            while next < byStart.count && byStart[next].start <= a {
                if byStart[next].end > a { active.append(byStart[next]) }
                next += 1
            }
            guard !active.isEmpty else { continue }
            // Winner: lowest rank, then source key for determinism.
            var best = active[0]
            for it in active.dropFirst() where (it.rank, it.sourceKey) < (best.rank, best.sourceKey) { best = it }
            // Sum every sample of the winning source covering this slice (a single
            // source occasionally writes overlapping samples, e.g. split uploads).
            let winners = active.filter { $0.sourceKey == best.sourceKey }
            let amount = winners.reduce(0) { $0 + $1.rate * (b - a) }
            let manual = winners.allSatisfy { $0.sample.isManual }
            let estimated = winners.contains { $0.sample.isEstimated }
            let seg = Segment(start: Date(timeIntervalSince1970: a), end: Date(timeIntervalSince1970: b), value: amount,
                              source: best.sample.source, isManual: manual, isEstimated: estimated)
            if var last = segments.last, last.end == seg.start, last.source == seg.source,
               last.isManual == seg.isManual, last.isEstimated == seg.isEstimated {
                last.end = seg.end
                last.value += seg.value
                segments[segments.count - 1] = last
            } else {
                segments.append(seg)
            }
        }
        return segments
    }

    /// Total over all segments.
    public static func total(_ samples: [Sample], priority: SourcePriority) -> Double {
        dedupe(samples, priority: priority).reduce(0) { $0 + $1.value }
    }

    /// Distributes segments into bins (e.g. days or hours), prorating segments
    /// that straddle a bin boundary.
    public static func bin(_ segments: [Segment], binStart: (Date) -> Date, binEnd: (Date) -> Date,
                           filter: (Segment) -> Bool = { _ in true }) -> [Date: Double] {
        var out: [Date: Double] = [:]
        for seg in segments where filter(seg) {
            var cursor = seg.start
            let total = seg.duration
            if total <= 0 {
                out[binStart(seg.start), default: 0] += seg.value
                continue
            }
            while cursor < seg.end {
                let bs = binStart(cursor)
                let be = min(binEnd(bs), seg.end)
                let part = be.timeIntervalSince(cursor) / total * seg.value
                out[bs, default: 0] += part
                if be <= cursor { break }
                cursor = be
            }
        }
        return out
    }

    /// Daily totals keyed by DayKey.
    public static func dailyTotals(_ samples: [Sample], priority: SourcePriority, calendar: Calendar,
                                   filter: (Segment) -> Bool = { _ in true }) -> [DayKey: Double] {
        let segs = dedupe(samples, priority: priority)
        let bins = bin(segs, binStart: { calendar.startOfDay(for: $0) },
                       binEnd: { calendar.date(byAdding: .day, value: 1, to: $0)! }, filter: filter)
        var out: [DayKey: Double] = [:]
        for (d, v) in bins { out[DayKey(d, calendar: calendar), default: 0] += v }
        return out
    }
}
