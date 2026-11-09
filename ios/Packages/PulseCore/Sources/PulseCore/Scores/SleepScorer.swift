import Foundation

/// Sleep Score (0–100). See /docs/scores.md §Sleep Score.
public enum SleepScorer {
    public static let weights = (duration: 0.40, efficiency: 0.20, consistency: 0.20, stages: 0.20)

    /// Duration sub-score: 100·min(1, r)^1.5 where r = asleep / goal; very long
    /// sleep (r > 1.3) loses up to 30 points.
    public static func durationScore(asleep: Double, goal: Double) -> Double {
        let r = asleep / max(goal, 1)
        if r > 1.3 { return ScoreMath.clamp(100 - (r - 1.3) * 100, 70, 100) }
        return 100 * pow(min(1, r), 1.5)
    }

    /// Efficiency 70% → 0, 95%+ → 100.
    public static func efficiencyScore(_ e: Double) -> Double {
        ScoreMath.clamp((e - 0.70) / 0.25 * 100)
    }

    /// Circular SD (minutes) of clock times; handles bedtimes around midnight.
    public static func circularSDMinutes(_ dates: [Date], calendar: Calendar) -> Double {
        let angles = dates.map { d -> Double in
            let c = calendar.dateComponents([.hour, .minute], from: d)
            return (Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0)) / 1440 * 2 * .pi
        }
        let s = angles.reduce(0) { $0 + sin($1) } / Double(angles.count)
        let co = angles.reduce(0) { $0 + cos($1) } / Double(angles.count)
        let r = max(1e-9, min(1, sqrt(s * s + co * co)))
        return sqrt(-2 * log(r)) / (2 * .pi) * 1440
    }

    /// Consistency: mean of onset/wake circular SD over ≤ 7 nights (≥ 3 needed).
    /// ≤ 15 min → 100, ≥ 90 min → 0.
    public static func consistencyScore(nights: [SleepNight], calendar: Calendar) -> (score: Double, sdMinutes: Double)? {
        let recent = Array(nights.suffix(7))
        guard recent.count >= 3 else { return nil }
        let sdOnset = circularSDMinutes(recent.map(\.sleepOnset), calendar: calendar)
        let sdWake = circularSDMinutes(recent.map(\.wakeTime), calendar: calendar)
        let sd = (sdOnset + sdWake) / 2
        return (ScoreMath.clamp(100 - (sd - 15) * (100 / 75)), sd)
    }

    /// Stage balance: deep 13–23 %, REM 20–25 % of asleep time. Inside the band
    /// = 100; falls linearly to 0 at 10 pts below / 15 pts above.
    public static func bandScore(_ pct: Double, lo: Double, hi: Double) -> Double {
        if pct >= lo && pct <= hi { return 100 }
        if pct < lo { return ScoreMath.clamp(100 * (1 - (lo - pct) / 10)) }
        return ScoreMath.clamp(100 * (1 - (pct - hi) / 15))
    }

    public static func stageScore(_ n: SleepNight) -> Double? {
        guard n.hasStages, n.asleepMinutes > 0 else { return nil }
        let deep = (n.stageMinutes[.deep] ?? 0) / n.asleepMinutes * 100
        let rem = (n.stageMinutes[.rem] ?? 0) / n.asleepMinutes * 100
        return (bandScore(deep, lo: 13, hi: 23) + bandScore(rem, lo: 20, hi: 25)) / 2
    }

    /// - Parameters:
    ///   - night: the night ending on `day`.
    ///   - previous: earlier nights (oldest first), used for consistency.
    public static func score(day: DayKey, night: SleepNight?, previous: [SleepNight], goalMinutes: Double, calendar: Calendar) -> ScoreResult {
        guard let n = night, n.asleepMinutes >= 60 else {
            return .insufficient(.sleep, day, reason: "No sleep recorded last night.", missing: ["Sleep"])
        }
        var used = ["Sleep duration"], missing: [String] = []
        let eff = n.efficiency
        if eff != nil { used.append("Time in bed") } else { missing.append("Time in bed") }
        let cons = consistencyScore(nights: previous + [n], calendar: calendar)
        if cons != nil { used.append("Bed/wake consistency") } else { missing.append("3+ nights for consistency") }
        let st = stageScore(n)
        if st != nil { used.append("Sleep stages") } else { missing.append("Sleep stages") }

        let (value, comps) = ScoreMath.combine([
            ("Duration", durationScore(asleep: n.asleepMinutes, goal: goalMinutes), weights.duration, n.asleepMinutes, goalMinutes, n.isEstimated),
            ("Efficiency", eff.map(efficiencyScore), weights.efficiency, eff.map { $0 * 100 }, nil, false),
            ("Consistency", cons?.score, weights.consistency, cons?.sdMinutes, nil, false),
            ("Stages", st, weights.stages, nil, nil, false),
        ])
        let conf: Confidence = comps.count >= 4 ? .high : (comps.count >= 3 ? .medium : .low)
        return ScoreResult(kind: .sleep, day: day, value: value.map { ($0 * 10).rounded() / 10 }, components: comps, inputsUsed: used,
                           missingInputs: missing, confidence: n.isEstimated ? min(conf, .medium) : conf, isEstimated: n.isEstimated)
    }
}
