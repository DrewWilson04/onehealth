import Foundation

/// One night of merged sleep.
public struct SleepNight: Sendable, Hashable, Codable {
    /// The local day the session *ended* on (wake day). "Last night" for a
    /// morning dashboard is the night whose `day` is today.
    public var day: DayKey
    public var start: Date
    public var end: Date
    /// Time in bed (union of in-bed samples and stage span), minutes.
    public var inBedMinutes: Double
    public var asleepMinutes: Double
    public var awakeMinutes: Double
    public var stageMinutes: [SleepStage: Double]
    /// True if the primary source provided deep/core/REM breakdown.
    public var hasStages: Bool
    public var primarySource: SourceRef
    public var sources: [String]
    public var segments: [Segment]
    public var isEstimated: Bool

    public var efficiency: Double? { inBedMinutes > 0 ? min(1, asleepMinutes / inBedMinutes) : nil }

    /// Bedtime = first asleep moment; wake = last asleep moment.
    public var sleepOnset: Date { segments.first(where: { SleepStage(rawValue: Int($0.value))?.isAsleep == true })?.start ?? start }
    public var wakeTime: Date { segments.last(where: { SleepStage(rawValue: Int($0.value))?.isAsleep == true })?.end ?? end }
}

/// Merges overlapping sleep sessions from multiple sources.
///
/// Algorithm (see /docs/schema.md §Dedup):
/// 1. In-bed samples are handled separately from stage samples (they are a
///    different dimension: efficiency = asleep / in bed).
/// 2. Stage samples are swept over elementary intervals; in each interval the
///    highest-priority covering source wins. Within one source, a specific
///    stage (core/deep/REM/awake) beats "asleep (unspecified)".
///    This prefers the best source for the whole night while still filling a
///    gap (e.g. the watch died at 4am) from the next-best source.
/// 3. Adjacent segments are coalesced, then grouped into nights: a gap of more
///    than `sessionGap` starts a new session; a night is keyed by its end day.
///    Sessions shorter than `minSessionMinutes` of sleep (naps) are kept but
///    are attached to the night only if they overlap the main window.
public enum SleepMerger {
    public static let sessionGap: TimeInterval = 2 * 3600

    public static func mergeSegments(_ samples: [Sample], priority: SourcePriority) -> (stages: [Segment], inBed: [Segment]) {
        let sleep = samples.filter { $0.type == .sleep && $0.end > $0.start }
        let stageSamples = sleep.filter { Int($0.value) != SleepStage.inBed.rawValue }
        let inBedSamples = sleep.filter { Int($0.value) == SleepStage.inBed.rawValue }
        return (sweep(stageSamples, priority: priority), sweep(inBedSamples, priority: priority))
    }

    static func specificity(_ code: Int) -> Int {
        switch SleepStage(rawValue: code) {
        case .deep, .core, .rem, .awake: return 0
        case .asleepUnspecified: return 1
        default: return 2
        }
    }

    static func sweep(_ samples: [Sample], priority: SourcePriority) -> [Segment] {
        guard !samples.isEmpty else { return [] }
        struct Item { let s: TimeInterval; let e: TimeInterval; let rank: Int; let key: String; let spec: Int; let sample: Sample }
        let items = samples.map { x in
            Item(s: x.start.timeIntervalSince1970, e: x.end.timeIntervalSince1970,
                 rank: priority.rank(x.source, device: x.device), key: x.source.key,
                 spec: specificity(Int(x.value)), sample: x)
        }.sorted { $0.s < $1.s }
        var bset = Set<TimeInterval>()
        for i in items { bset.insert(i.s); bset.insert(i.e) }
        let bounds = bset.sorted()
        var out: [Segment] = []
        var active: [Item] = []
        var next = 0
        for bi in 0..<(bounds.count - 1) {
            let a = bounds[bi], b = bounds[bi + 1]
            active.removeAll { $0.e <= a }
            while next < items.count && items[next].s <= a {
                if items[next].e > a { active.append(items[next]) }
                next += 1
            }
            guard var best = active.first else { continue }
            for it in active.dropFirst() where (it.rank, it.key, it.spec) < (best.rank, best.key, best.spec) { best = it }
            let seg = Segment(start: Date(timeIntervalSince1970: a), end: Date(timeIntervalSince1970: b),
                              value: best.sample.value, source: best.sample.source,
                              isManual: best.sample.isManual, isEstimated: best.sample.isEstimated)
            if var last = out.last, last.end == seg.start, last.value == seg.value, last.source == seg.source {
                last.end = seg.end
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }
        return out
    }

    public static func nights(_ samples: [Sample], priority: SourcePriority, calendar: Calendar) -> [SleepNight] {
        let (stages, inBed) = mergeSegments(samples, priority: priority)
        // Group stage + inBed segments into sessions by time proximity.
        let all = (stages.map { ($0, false) } + inBed.map { ($0, true) }).sorted { $0.0.start < $1.0.start }
        var sessions: [[(Segment, Bool)]] = []
        var currentEnd: Date?
        for item in all {
            if let ce = currentEnd, item.0.start.timeIntervalSince(ce) <= sessionGap {
                sessions[sessions.count - 1].append(item)
                currentEnd = max(ce, item.0.end)
            } else {
                sessions.append([item])
                currentEnd = item.0.end
            }
        }
        var nightsByDay: [DayKey: SleepNight] = [:]
        for session in sessions {
            let stageSegs = session.filter { !$0.1 }.map(\.0)
            let bedSegs = session.filter { $0.1 }.map(\.0)
            var stageMinutes: [SleepStage: Double] = [:]
            for s in stageSegs {
                if let st = SleepStage(rawValue: Int(s.value)) { stageMinutes[st, default: 0] += s.duration / 60 }
            }
            let asleep = stageMinutes.filter { $0.key.isAsleep }.values.reduce(0, +)
            let awake = stageMinutes[.awake] ?? 0
            // In-bed = union of in-bed and all stage segments.
            let inBedMin = unionMinutes(session.map(\.0))
            let start = session.map(\.0.start).min()!
            let end = session.map(\.0.end).max()!
            // Primary source = source contributing most asleep time.
            var bySource: [SourceRef: Double] = [:]
            for s in stageSegs where SleepStage(rawValue: Int(s.value))?.isAsleep == true { bySource[s.source, default: 0] += s.duration }
            if bySource.isEmpty { for s in bedSegs { bySource[s.source, default: 0] += s.duration } }
            let primary = bySource.max { a, b in a.value == b.value ? a.key.key > b.key.key : a.value < b.value }!.key
            let hasStages = stageSegs.contains { s in
                s.source == primary && [SleepStage.core, .deep, .rem].contains(SleepStage(rawValue: Int(s.value)))
            }
            let day = DayKey(end, calendar: calendar)
            let night = SleepNight(day: day, start: start, end: end, inBedMinutes: inBedMin, asleepMinutes: asleep,
                                   awakeMinutes: awake, stageMinutes: stageMinutes, hasStages: hasStages, primarySource: primary,
                                   sources: Array(Set(session.map(\.0.source.key))).sorted(),
                                   segments: stageSegs, isEstimated: stageSegs.contains { $0.isEstimated })
            if let existing = nightsByDay[day] {
                // Two sessions ending the same day (e.g. nap + night): keep the
                // longer as the night; naps are folded in as extra asleep time
                // only when they start after 18:00 the previous day (split night).
                let main = existing.asleepMinutes >= night.asleepMinutes ? existing : night
                let other = main == existing ? night : existing
                let splitNight = abs(other.end.timeIntervalSince(main.start)) < 4 * 3600 || abs(main.end.timeIntervalSince(other.start)) < 4 * 3600
                if splitNight {
                    var merged = main
                    merged.start = min(main.start, other.start)
                    merged.end = max(main.end, other.end)
                    merged.asleepMinutes += other.asleepMinutes
                    merged.awakeMinutes += other.awakeMinutes
                    merged.inBedMinutes += other.inBedMinutes
                    for (k, v) in other.stageMinutes { merged.stageMinutes[k, default: 0] += v }
                    merged.segments = (main.segments + other.segments).sorted { $0.start < $1.start }
                    merged.sources = Array(Set(main.sources + other.sources)).sorted()
                    nightsByDay[day] = merged
                } else {
                    nightsByDay[day] = main
                }
            } else {
                nightsByDay[day] = night
            }
        }
        return nightsByDay.values.sorted { $0.day < $1.day }
    }

    static func unionMinutes(_ segs: [Segment]) -> Double {
        let sorted = segs.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var curS: Date?, curE: Date?
        for s in sorted {
            if let ce = curE, s.start <= ce {
                curE = max(ce, s.end)
            } else {
                if let cs = curS, let ce = curE { total += ce.timeIntervalSince(cs) }
                curS = s.start
                curE = s.end
            }
        }
        if let cs = curS, let ce = curE { total += ce.timeIntervalSince(cs) }
        return total / 60
    }
}
