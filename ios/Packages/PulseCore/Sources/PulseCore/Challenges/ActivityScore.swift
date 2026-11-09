import Foundation

/// Measured, competition-eligible inputs for one day. Callers MUST exclude
/// manual entries (HKWasUserEntered) and estimated/gap-filled values.
public struct ActivityInputs: Codable, Sendable, Hashable {
    public var steps: Double?
    /// Apple Exercise minutes (Apple Watch) when available.
    public var exerciseMinutes: Double?
    /// Minutes in HR zones 1–5 (any HR device: Garmin, WHOOP, Oura, Fitbit…).
    public var zoneMinutes: [Int: Double]
    /// Recorded workout duration (minutes), for devices without HR.
    public var workoutMinutes: Double?
    public var sleepMinutes: Double?

    public init(steps: Double? = nil, exerciseMinutes: Double? = nil, zoneMinutes: [Int: Double] = [:],
                workoutMinutes: Double? = nil, sleepMinutes: Double? = nil) {
        self.steps = steps
        self.exerciseMinutes = exerciseMinutes
        self.zoneMinutes = zoneMinutes
        self.workoutMinutes = workoutMinutes
        self.sleepMinutes = sleepMinutes
    }

    /// Builds inputs from normalized samples, dropping manual/estimated ones.
    public static func from(samples: [Sample], nights: [SleepNight], zoneMinutes: [Int: Double], day: DayKey,
                            calendar: Calendar, priority: SourcePriority = .default) -> ActivityInputs {
        let eligible = samples.filter(\.isCompetitionEligible)
        func total(_ id: MetricID) -> Double? {
            let s = eligible.filter { $0.type == id }
            guard !s.isEmpty else { return nil }
            return CumulativeDeduper.dailyTotals(s, priority: priority, calendar: calendar)[day]
        }
        let workouts = WorkoutMerger.merge(eligible.filter { $0.type == .workout && DayKey($0.start, calendar: calendar) == day }, priority: priority)
        let night = nights.first { $0.day == day && !$0.isEstimated && !$0.segments.contains(where: \.isManual) }
        return ActivityInputs(steps: total(.steps), exerciseMinutes: total(.exerciseTime), zoneMinutes: zoneMinutes,
                              workoutMinutes: workouts.isEmpty ? nil : workouts.reduce(0) { $0 + $1.value },
                              sleepMinutes: night?.asleepMinutes)
    }
}

public struct ActivityScoreBreakdown: Codable, Sendable, Hashable {
    public var steps: Double
    public var activeMinutes: Double
    public var intensity: Double
    public var sleep: Double
    public var total: Double { steps + activeMinutes + intensity + sleep }
}

/// Device-agnostic daily Activity Score (0–100). See /docs/challenges.md.
///
///   steps     30 pts  = 30 · min(steps, 15 000) / 15 000
///   active    30 pts  = 30 · min(A, 90) / 90,  A = max(exercise min, zone 2–5 min)
///   intensity 25 pts  = 25 · min(W, 120) / 120, W = Σ zone-weighted minutes
///                       (Z1 0.5, Z2 1, Z3 1.5, Z4 2, Z5 2.5) or, with no HR,
///                       workout minutes × 1.0
///   sleep     15 pts  = 15 for 7–9 h, 7 for 6–7 h or 9–10 h, else 0
///
/// Caps stop any single device-specific metric from dominating, and taking the
/// max of "exercise minutes" and "zone minutes" lets Apple Watch users (who
/// have both) compete fairly with Garmin/WHOOP/Oura/Fitbit users (zones only).
public enum ActivityScore {
    public static let stepCap = 15_000.0
    public static let activeCap = 90.0
    public static let intensityCap = 120.0
    public static let zoneWeights: [Int: Double] = [1: 0.5, 2: 1.0, 3: 1.5, 4: 2.0, 5: 2.5]

    public static func breakdown(_ i: ActivityInputs) -> ActivityScoreBreakdown {
        let steps = 30 * min(i.steps ?? 0, stepCap) / stepCap
        let zoneActive = (2...5).reduce(0.0) { $0 + (i.zoneMinutes[$1] ?? 0) }
        let active = max(i.exerciseMinutes ?? 0, zoneActive)
        let activePts = 30 * min(active, activeCap) / activeCap
        var weighted = i.zoneMinutes.reduce(0.0) { $0 + $1.value * (zoneWeights[$1.key] ?? 0) }
        if i.zoneMinutes.isEmpty { weighted = i.workoutMinutes ?? 0 }
        let intensity = 25 * min(weighted, intensityCap) / intensityCap
        var sleep = 0.0
        if let s = i.sleepMinutes {
            if s >= 420 && s <= 540 { sleep = 15 } else if (s >= 360 && s < 420) || (s > 540 && s <= 600) { sleep = 7 }
        }
        func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        return ActivityScoreBreakdown(steps: r(steps), activeMinutes: r(activePts), intensity: r(intensity), sleep: sleep)
    }

    public static func score(_ i: ActivityInputs) -> Double { (breakdown(i).total * 100).rounded() / 100 }
}
