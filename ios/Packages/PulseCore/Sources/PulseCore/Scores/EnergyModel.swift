import Foundation

/// Energy (0–100, Body Battery-style). See /docs/scores.md §Energy.
///
/// Simulated at 15-minute resolution from wake time:
///   start  = 20 + 80 · (0.6 · SleepScore + 0.4 · HRVsub) / 100
///   each slot: − activity (0.25 / TRIMP unit)
///              − stress   (still, HR > RHR+15, not in a workout): 0.08 · (HR − RHR − 15), ≤ 2
///              − baseline 0.15 (≈ 0.6 / h awake)
///              + rest     (still, HR ≤ RHR+5): +0.3
///              + sleep/nap segments: +1.5 · (1 − E/100)
public enum EnergyModel {
    public static let slot: TimeInterval = 15 * 60
    public static let activityDrainPerTRIMP = 0.25
    public static let baselineDrainPerSlot = 0.15
    public static let restRecharge = 0.3
    public static let sleepRechargeMax = 1.5
    public static let stillSteps = 50.0

    public struct Slot: Sendable {
        public var start: Date
        public var avgHR: Double?
        public var steps: Double
        public var inWorkout: Bool
        public var asleep: Bool
        public var estimatedHR: Bool
        public init(start: Date, avgHR: Double?, steps: Double, inWorkout: Bool = false, asleep: Bool = false, estimatedHR: Bool = false) {
            self.start = start
            self.avgHR = avgHR
            self.steps = steps
            self.inWorkout = inWorkout
            self.asleep = asleep
            self.estimatedHR = estimatedHR
        }
    }

    public static func startValue(sleepScore: Double, hrvSubScore: Double?) -> Double {
        let recovery = hrvSubScore.map { 0.6 * sleepScore + 0.4 * $0 } ?? sleepScore
        return ScoreMath.clamp(20 + 0.8 * recovery)
    }

    public static func simulate(start: Double, slots: [Slot], profile: HRProfile) -> (end: Double, series: [Double], drained: Double, charged: Double) {
        var e = start
        var series: [Double] = []
        var drained = 0.0, charged = 0.0
        let (k1, k2) = profile.sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        for s in slots {
            var delta = 0.0
            if s.asleep {
                delta += sleepRechargeMax * (1 - e / 100)
            } else {
                delta -= baselineDrainPerSlot
                if let hr = s.avgHR {
                    let x = profile.hrr(hr)
                    if x >= StrainScorer.minHRR {
                        delta -= activityDrainPerTRIMP * 15 * x * k1 * exp(k2 * x)
                    } else if s.steps < stillSteps && !s.inWorkout {
                        let over = hr - profile.restingHR - 15
                        if over > 0 { delta -= min(2, 0.08 * over) }
                        else if hr <= profile.restingHR + 5 { delta += restRecharge }
                    }
                }
            }
            if delta < 0 { drained -= delta } else { charged += delta }
            e = ScoreMath.clamp(e + delta)
            series.append((e * 10).rounded() / 10)
        }
        return (e, series, drained, charged)
    }

    public static func score(day: DayKey, sleep: ScoreResult?, hrvSubScore: Double?, slots: [Slot], profile: HRProfile?) -> ScoreResult {
        guard let s = sleep?.value else {
            return .insufficient(.energy, day, reason: "Energy starts from last night's recovery — no sleep recorded.", missing: ["Sleep"])
        }
        guard let profile else {
            return .insufficient(.energy, day, reason: "Energy needs a resting heart rate baseline.", missing: ["Resting HR"])
        }
        let withHR = slots.filter { $0.avgHR != nil }
        let coverage = slots.isEmpty ? 0 : Double(withHR.count) / Double(slots.count)
        guard coverage >= 0.25 else {
            return .insufficient(.energy, day, reason: "Not enough heart-rate data today to estimate energy.",
                                 missing: ["Daytime heart rate"], used: ["Sleep Score"])
        }
        let start = startValue(sleepScore: s, hrvSubScore: hrvSubScore)
        let r = simulate(start: start, slots: slots, profile: profile)
        let estimated = slots.contains(where: \.estimatedHR) || sleep?.isEstimated == true
        var used = ["Sleep Score"]
        var missing: [String] = []
        if hrvSubScore != nil { used.append("Overnight HRV") } else { missing.append("Overnight HRV") }
        if !withHR.isEmpty { used.append("Daytime heart rate") } else { missing.append("Daytime heart rate") }
        if slots.contains(where: { $0.steps > 0 }) { used.append("Steps") }
        var conf: Confidence = coverage > 0.7 ? .high : (coverage > 0.35 ? .medium : .low)
        if estimated { conf = min(conf, .medium) }
        return ScoreResult(kind: .energy, day: day, value: (r.end * 10).rounded() / 10, inputsUsed: used, missingInputs: missing,
                           confidence: conf, isEstimated: estimated,
                           extras: ["start": (start * 10).rounded() / 10, "drained": r.drained, "charged": r.charged],
                           series: r.series)
    }

    /// Buckets HR points / steps / workouts / sleep into 15-minute slots.
    public static func slots(from: Date, to: Date, hr: [HRPoint], steps: [(Date, Double)], workouts: [DateInterval],
                             sleep: [DateInterval], fillGaps: Bool = true) -> [Slot] {
        guard to > from else { return [] }
        let n = Int(ceil(to.timeIntervalSince(from) / slot))
        var hrSum = [Double](repeating: 0, count: n), hrN = [Int](repeating: 0, count: n)
        var st = [Double](repeating: 0, count: n)
        for p in hr {
            let i = Int(p.time.timeIntervalSince(from) / slot)
            if i >= 0 && i < n { hrSum[i] += p.bpm; hrN[i] += 1 }
        }
        for (d, v) in steps {
            let i = Int(d.timeIntervalSince(from) / slot)
            if i >= 0 && i < n { st[i] += v }
        }
        var raw: [(Date, Double)] = []
        for i in 0..<n where hrN[i] > 0 { raw.append((from.addingTimeInterval(Double(i) * slot), hrSum[i] / Double(hrN[i]))) }
        var hrBySlot: [Int: (Double, Bool)] = [:]
        let filled = fillGaps ? GapFiller.fillSeries(raw, step: slot) : raw.map { ($0.0, $0.1, false) }
        for (d, v, est) in filled {
            let i = Int((d.timeIntervalSince(from) / slot).rounded())
            if i >= 0 && i < n { hrBySlot[i] = (v, est) }
        }
        return (0..<n).map { i in
            let t = from.addingTimeInterval(Double(i) * slot)
            let mid = t.addingTimeInterval(slot / 2)
            return Slot(start: t, avgHR: hrBySlot[i]?.0, steps: st[i],
                        inWorkout: workouts.contains { $0.contains(mid) }, asleep: sleep.contains { $0.contains(mid) },
                        estimatedHR: hrBySlot[i]?.1 ?? false)
        }
    }
}
