import Foundation
import PulseCore

/// Assembles `ScoreInputs` from the local cache + HealthKit and caches
/// results per day. Recomputes only dirty days (and today).
public actor ScoreService {
    let provider: HealthKitProvider
    let store: LocalStore
    var calendar: Calendar
    var preferredSources: [MetricID: String] = [:]
    var priority: SourcePriority = .default
    var sleepGoalMinutes: Double = 480
    static let loadKind = "load"

    public init(provider: HealthKitProvider, store: LocalStore, calendar: Calendar = .pulse()) {
        self.provider = provider
        self.store = store
        self.calendar = calendar
    }

    public func configure(preferredSources: [MetricID: String], priority: SourcePriority, sleepGoalMinutes: Double) {
        self.preferredSources = preferredSources
        self.priority = priority
        self.sleepGoalMinutes = sleepGoalMinutes
    }

    // MARK: Public API

    /// Cached scores for `day`; computes (and caches) if missing or `force`.
    public func scores(for day: DayKey, force: Bool = false) async -> [ScoreKind: ScoreResult] {
        if !force {
            var cached: [ScoreKind: ScoreResult] = [:]
            for k in ScoreKind.allCases {
                if let r = (try? await store.scores(k.rawValue, from: day, to: day, as: ScoreResult.self))?[day] { cached[k] = r }
            }
            if cached.count == ScoreKind.allCases.count { return cached }
        }
        let inputs = await inputs(for: day)
        let results = ScoreEngine.computeAll(inputs)
        for (k, r) in results { try? await store.saveScore(k.rawValue, day: day, value: r) }
        if let t = results[.strain]?.extras["trimp"] { try? await store.saveScore(Self.loadKind, day: day, value: t) }
        return results
    }

    /// Score history from the cache, computing missing days (Readiness and
    /// Sleep only need cached data, so this is cheap).
    public func history(_ kind: ScoreKind, from: DayKey, to: DayKey) async -> [ScoreResult] {
        var cached = (try? await store.scores(kind.rawValue, from: from, to: to, as: ScoreResult.self)) ?? [:]
        let cheap = kind == .readiness || kind == .sleep
        if cheap {
            for d in DayKey.range(from, through: to) where cached[d] == nil {
                let inputs = await inputs(for: d, includeIntraday: false)
                let r = ScoreEngine.computeAll(inputs)
                if let v = r[kind] {
                    cached[d] = v
                    if d < DayKey(Date(), calendar: calendar) { try? await store.saveScore(kind.rawValue, day: d, value: v) }
                }
            }
        }
        return cached.values.sorted { $0.day < $1.day }
    }

    /// Called after ingestion with dirty days.
    public func invalidate(_ days: Set<DayKey>) async {
        try? await store.invalidateScores(days: days)
    }

    // MARK: Inputs

    func inputs(for day: DayKey, includeIntraday: Bool = true) async -> ScoreInputs {
        let cal = calendar
        let from = day.addingDays(-31)
        let dayStart = day.start(in: cal)
        let dayEnd = day.addingDays(1).start(in: cal)
        let now = min(Date(), dayEnd)

        // HRV per source, overnight window (previous 20:00 → 10:00) keyed to
        // the wake day; falls back to the day's mean when no overnight reading.
        let hrvSamples = (try? await store.samples(.hrv, from: from.start(in: cal).addingTimeInterval(-4 * 3600), to: dayEnd)) ?? []
        var bySource: [String: [DayKey: [Double]]] = [:]
        var anyByDay: [String: [DayKey: [Double]]] = [:]
        for s in hrvSamples where !s.isEstimated {
            let k = DayKey(s.start, calendar: cal)
            anyByDay[s.source.key, default: [:]][k, default: []].append(s.value)
            let hour = cal.component(.hour, from: s.start)
            let night = hour >= 20 ? k.addingDays(1) : (hour < 10 ? k : nil)
            if let night { bySource[s.source.key, default: [:]][night, default: []].append(s.value) }
        }
        var hrv: [String: [DayKey: Double]] = [:]
        for (src, days) in anyByDay {
            var merged: [DayKey: Double] = [:]
            for (d, vs) in days { merged[d] = vs.reduce(0, +) / Double(vs.count) }
            for (d, vs) in bySource[src] ?? [:] { merged[d] = vs.reduce(0, +) / Double(vs.count) }
            hrv[src] = merged.filter { $0.key >= from && $0.key <= day }
        }

        let rhrRows = (try? await store.aggregates(.restingHeartRate, period: .day, from: from, to: day)) ?? []
        let rhr = Dictionary(rhrRows.filter { !$0.isEstimated }.compactMap { r in (r.average ?? r.latest).map { (r.day, $0) } },
                             uniquingKeysWith: { a, _ in a })

        let sleepSamples = (try? await store.samples(.sleep, from: day.addingDays(-9).start(in: cal), to: dayEnd)) ?? []
        let sleepPriority = priority.preferring(preferredSources[.sleep])
        let nights = Dictionary(SleepMerger.nights(sleepSamples, priority: sleepPriority, calendar: cal).map { ($0.day, $0) },
                                uniquingKeysWith: { a, _ in a })

        var hr: [HRPoint] = []
        var steps: [(Date, Double)] = []
        var workouts: [DateInterval] = []
        var load: [DayKey: Double] = [:]
        var observedMax: Double?
        if includeIntraday {
            let iv = DateInterval(start: dayStart, end: max(dayStart.addingTimeInterval(60), now))
            hr = (try? await provider.heartRateSeries(iv, calendar: cal)) ?? []
            steps = (try? await provider.stepBuckets(iv, calendar: cal)) ?? []
            workouts = ((try? await store.samples(.workout, from: dayStart, to: dayEnd)) ?? [])
                .map { DateInterval(start: $0.start, end: $0.end) }
            load = await loadHistory(before: day)
            let maxRows = (try? await store.aggregates(.heartRate, period: .month, from: day.addingDays(-365), to: day)) ?? []
            observedMax = maxRows.compactMap(\.max).max()
        }

        return ScoreInputs(day: day, calendar: cal, hrvBySource: hrv, preferredHRVSource: preferredSources[.hrv],
                           restingHR: rhr, nights: nights, sleepGoalMinutes: sleepGoalMinutes, heartRate: hr, steps: steps,
                           workouts: workouts, loadHistory: load, age: provider.age(), sex: provider.biologicalSex(),
                           observedMaxHR: observedMax, now: now)
    }

    /// Daily TRIMP for the 28 days before `day` (cached; missing days are
    /// computed once from HealthKit minute HR).
    func loadHistory(before day: DayKey) async -> [DayKey: Double] {
        let from = day.addingDays(-StrainScorer.chronicDays), to = day.addingDays(-1)
        var load = (try? await store.scores(Self.loadKind, from: from, to: to, as: Double.self)) ?? [:]
        let rhrRows = (try? await store.aggregates(.restingHeartRate, period: .day, from: from.addingDays(-30), to: to)) ?? []
        let rest = rhrRows.compactMap(\.average).reduce(0, +) / Double(max(1, rhrRows.count))
        guard rest > 0 else { return load }
        let profile = HRProfile(maxHR: HRProfile.estimateMaxHR(age: provider.age(), observedMax: nil), restingHR: rest, sex: provider.biologicalSex())
        for d in DayKey.range(from, through: to) where load[d] == nil {
            let iv = d.interval(in: calendar)
            guard let pts = try? await provider.heartRateSeries(iv, calendar: calendar), pts.count >= 10 else { continue }
            let t = StrainScorer.trimp(pts, profile: profile)
            load[d] = t
            try? await store.saveScore(Self.loadKind, day: d, value: t)
        }
        return load
    }
}
