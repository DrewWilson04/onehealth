import Foundation

public struct StreakInfo: Codable, Sendable, Hashable {
    /// Consecutive periods met, ending with the current period if it is
    /// already met, otherwise ending with the previous period ("in progress"
    /// periods never break a streak until they are over).
    public var current: Int
    public var longest: Int
    public var metCurrentPeriod: Bool
    /// Value so far in the current period.
    public var currentValue: Double?
    public var progress: Double
    /// Last 7 periods, oldest first (for dots UI).
    public var recent: [Bool]
}

/// Goal streaks. Daily goals compare each day's value; weekly goals compare
/// the ISO-week total (sum metrics) or mean (average metrics). Estimated
/// (gap-filled) values never count toward a streak — callers pass only
/// measured values.
public enum Streaks {
    public static func compute(goal: Goal, metric: MetricType, daily: [DayKey: Double], today: DayKey) -> StreakInfo {
        switch goal.period {
        case .day:
            return run(goal: goal, today: today, step: { $0.addingDays(-1) }, value: { daily[$0] }, start: today)
        case .week:
            let isSum = [.sum, .durationMinutes, .count].contains(metric.dailyStatistic)
            func weekValue(_ weekStart: DayKey) -> Double? {
                let vals = (0..<7).compactMap { daily[weekStart.addingDays($0)] }
                guard !vals.isEmpty else { return nil }
                let total = vals.reduce(0, +)
                return isSum ? total : total / Double(vals.count)
            }
            return run(goal: goal, today: today, step: { $0.addingDays(-7) }, value: weekValue, start: today.weekStart)
        }
    }

    private static func run(goal: Goal, today: DayKey, step: (DayKey) -> DayKey, value: (DayKey) -> Double?, start: DayKey) -> StreakInfo {
        let currentValue = value(start)
        let metNow = goal.isMet(currentValue)
        // Current streak.
        var current = metNow ? 1 : 0
        var cursor = step(start)
        while goal.isMet(value(cursor)) {
            current += 1
            cursor = step(cursor)
        }
        // Longest streak over the history window (10 years max).
        var longest = 0, run = 0
        var c = start
        var seenAny = false
        for _ in 0..<(366 * 10) {
            let v = value(c)
            if v != nil { seenAny = true }
            if goal.isMet(v) { run += 1; longest = max(longest, run) } else if c != start { run = 0 }
            c = step(c)
            if !seenAny && DayKey.daysBetween(c, start) > 400 { break }
        }
        longest = max(longest, current)
        var recent: [Bool] = []
        var r = start
        for _ in 0..<7 { recent.append(goal.isMet(value(r))); r = step(r) }
        return StreakInfo(current: current, longest: longest, metCurrentPeriod: metNow, currentValue: currentValue,
                          progress: goal.progress(currentValue), recent: recent.reversed())
    }
}
