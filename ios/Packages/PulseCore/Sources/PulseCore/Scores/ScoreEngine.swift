import Foundation

/// Everything the engine needs for one day. Assembled by the platform layer
/// (PulseKit on iOS, web/src on web) from local data.
public struct ScoreInputs: Sendable {
    public var day: DayKey
    public var calendar: Calendar
    /// Daily HRV per source key (ms). Baselines are per source.
    public var hrvBySource: [String: [DayKey: Double]]
    public var preferredHRVSource: String?
    public var restingHR: [DayKey: Double]
    /// Nights keyed by wake day (≥ 7 previous nights for consistency).
    public var nights: [DayKey: SleepNight]
    public var sleepGoalMinutes: Double
    /// Today's heart-rate series (for Strain/Energy).
    public var heartRate: [HRPoint]
    /// Today's step counts in small buckets (Date = bucket start).
    public var steps: [(Date, Double)]
    public var workouts: [DateInterval]
    /// Previous days' TRIMP (cached) for the training-load ratio.
    public var loadHistory: [DayKey: Double]
    public var age: Double?
    public var sex: BiologicalSex
    public var observedMaxHR: Double?
    /// End of the simulation window for Energy (now, or end of day).
    public var now: Date

    public init(day: DayKey, calendar: Calendar, hrvBySource: [String: [DayKey: Double]], preferredHRVSource: String? = nil,
                restingHR: [DayKey: Double], nights: [DayKey: SleepNight], sleepGoalMinutes: Double = 480,
                heartRate: [HRPoint] = [], steps: [(Date, Double)] = [], workouts: [DateInterval] = [],
                loadHistory: [DayKey: Double] = [:], age: Double? = nil, sex: BiologicalSex = .unknown,
                observedMaxHR: Double? = nil, now: Date) {
        self.day = day
        self.calendar = calendar
        self.hrvBySource = hrvBySource
        self.preferredHRVSource = preferredHRVSource
        self.restingHR = restingHR
        self.nights = nights
        self.sleepGoalMinutes = sleepGoalMinutes
        self.heartRate = heartRate
        self.steps = steps
        self.workouts = workouts
        self.loadHistory = loadHistory
        self.age = age
        self.sex = sex
        self.observedMaxHR = observedMaxHR
        self.now = now
    }
}

/// Computes all four scores for a day from whatever inputs are available.
public enum ScoreEngine {
    /// Picks the HRV source: preferred if it has today's (or yesterday's)
    /// value, else the source with the most days in the last 30.
    public static func hrvSource(_ i: ScoreInputs) -> String? {
        if let p = i.preferredHRVSource, let s = i.hrvBySource[p], !s.isEmpty { return p }
        return i.hrvBySource.max { a, b in
            let ca = a.value.keys.filter { DayKey.daysBetween($0, i.day) <= 30 }.count
            let cb = b.value.keys.filter { DayKey.daysBetween($0, i.day) <= 30 }.count
            return ca == cb ? a.key > b.key : ca < cb
        }?.key
    }

    public static func profile(_ i: ScoreInputs) -> HRProfile? {
        let rhrBase = Baseline.compute(i.restingHR, before: i.day, minDays: 3)?.mean ?? i.restingHR[i.day]
        guard let rest = rhrBase else { return nil }
        return HRProfile(maxHR: HRProfile.estimateMaxHR(age: i.age, observedMax: i.observedMaxHR), restingHR: rest, sex: i.sex)
    }

    public static func computeAll(_ i: ScoreInputs) -> [ScoreKind: ScoreResult] {
        let d = i.day
        // Sleep
        let prev = (1...7).compactMap { i.nights[d.addingDays(-$0)] }.sorted { $0.day < $1.day }
        let sleep = SleepScorer.score(day: d, night: i.nights[d], previous: prev, goalMinutes: i.sleepGoalMinutes, calendar: i.calendar)

        // Readiness with short-gap filling for today's HRV / RHR
        let src = hrvSource(i)
        let hrv = src.flatMap { i.hrvBySource[$0] } ?? [:]
        let hrvFill = hrv[d] == nil ? GapFiller.fillDaily(hrv, from: d, through: d)[d] : nil
        let rhrFill = i.restingHR[d] == nil ? GapFiller.fillDaily(i.restingHR, from: d, through: d)[d] : nil
        let readiness = ReadinessScorer.score(day: d, .init(hrv: hrv, hrvTodayFilled: hrvFill, rhr: i.restingHR,
                                                             rhrTodayFilled: rhrFill, sleep: sleep.value == nil ? nil : sleep))

        // Strain
        let prof = profile(i)
        let strain = StrainScorer.score(day: d, hr: i.heartRate, profile: prof, history: i.loadHistory)

        // Energy: from wake time (or start of day) to now.
        let dayStart = d.start(in: i.calendar)
        let wake = i.nights[d]?.wakeTime ?? dayStart
        let end = min(i.now, d.addingDays(1).start(in: i.calendar))
        let naps = i.nights.values.filter { $0.day == d }.flatMap { $0.segments }.filter { $0.start >= wake }
            .map { DateInterval(start: $0.start, end: $0.end) }
        let slots = EnergyModel.slots(from: max(wake, dayStart), to: end, hr: i.heartRate, steps: i.steps,
                                      workouts: i.workouts, sleep: naps)
        let hrvSub = readiness.components.first { $0.name == "HRV" }?.score
        let energy = EnergyModel.score(day: d, sleep: sleep.value == nil ? nil : sleep, hrvSubScore: hrvSub, slots: slots, profile: prof)

        return [.sleep: sleep, .readiness: readiness, .strain: strain, .energy: energy]
    }
}
