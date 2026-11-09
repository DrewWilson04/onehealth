import Foundation

/// Readiness (0–100). See /docs/scores.md §Readiness.
///
/// HRV and resting HR are scored against the user's own 30-day baseline
/// (≥ 10 days required) from the *same source*, because devices measure HRV
/// differently. Sleep contributes the Sleep Score.
public enum ReadinessScorer {
    public static let weights = (hrv: 0.40, rhr: 0.25, sleep: 0.35)
    /// Floors stop tiny baseline SDs from producing extreme z-scores.
    public static let minLnHRVSD = 0.10
    public static let minRHRSD = 2.0

    /// z = 0 → ≈ 65, +1 SD → ≈ 86, −1 SD → ≈ 35.
    public static func hrvScore(z: Double) -> Double { 100 * ScoreMath.logistic(0.6 + 1.2 * z) }
    /// Higher RHR than baseline is worse.
    public static func rhrScore(z: Double) -> Double { 100 * ScoreMath.logistic(0.6 - 1.2 * z) }

    public struct Inputs: Sendable {
        /// Daily HRV (ms) from ONE source, keyed by day. May include gap-filled
        /// values for `day` (passed separately via `hrvTodayFilled`).
        public var hrv: [DayKey: Double]
        public var hrvTodayFilled: FilledValue?
        public var rhr: [DayKey: Double]
        public var rhrTodayFilled: FilledValue?
        public var sleep: ScoreResult?
        public init(hrv: [DayKey: Double], hrvTodayFilled: FilledValue? = nil, rhr: [DayKey: Double],
                    rhrTodayFilled: FilledValue? = nil, sleep: ScoreResult?) {
            self.hrv = hrv
            self.hrvTodayFilled = hrvTodayFilled
            self.rhr = rhr
            self.rhrTodayFilled = rhrTodayFilled
            self.sleep = sleep
        }
    }

    public static func score(day: DayKey, _ i: Inputs) -> ScoreResult {
        var used: [String] = [], missing: [String] = []
        var estimated = false
        var worstConf: Confidence = .high

        // HRV
        var hrvPart: (score: Double?, raw: Double?, base: Double?, est: Bool) = (nil, nil, nil, false)
        let hrvBase = Baseline.compute(i.hrv, before: day, logTransform: true)
        let hrvToday = i.hrv[day].map { FilledValue(value: $0, isEstimated: false, confidence: nil) } ?? i.hrvTodayFilled
        if let b = hrvBase, let t = hrvToday, t.value > 0 {
            let z = (log(t.value) - b.mean) / max(b.sd, minLnHRVSD)
            hrvPart = (hrvScore(z: z), t.value, exp(b.mean), t.isEstimated)
            used.append("HRV vs 30-day baseline")
            if t.isEstimated { estimated = true; worstConf = min(worstConf, t.confidence ?? .low) }
        } else {
            missing.append(hrvBase == nil ? "10+ days of HRV" : "Last night's HRV")
        }

        // Resting HR
        var rhrPart: (score: Double?, raw: Double?, base: Double?, est: Bool) = (nil, nil, nil, false)
        let rhrBase = Baseline.compute(i.rhr, before: day)
        let rhrToday = i.rhr[day].map { FilledValue(value: $0, isEstimated: false, confidence: nil) } ?? i.rhrTodayFilled
        if let b = rhrBase, let t = rhrToday {
            let z = (t.value - b.mean) / max(b.sd, minRHRSD)
            rhrPart = (rhrScore(z: z), t.value, b.mean, t.isEstimated)
            used.append("Resting HR vs 30-day baseline")
            if t.isEstimated { estimated = true; worstConf = min(worstConf, t.confidence ?? .low) }
        } else {
            missing.append(rhrBase == nil ? "10+ days of resting HR" : "Today's resting HR")
        }

        guard hrvPart.score != nil || rhrPart.score != nil else {
            return .insufficient(.readiness, day, reason: "Readiness needs at least 10 days of HRV or resting heart rate, plus today's reading.",
                                 missing: missing, used: used)
        }

        if let s = i.sleep?.value {
            used.append("Sleep Score")
            if i.sleep?.isEstimated == true { estimated = true }
            _ = s
        } else {
            missing.append("Last night's sleep")
        }

        let (value, comps) = ScoreMath.combine([
            ("HRV", hrvPart.score, weights.hrv, hrvPart.raw, hrvPart.base, hrvPart.est),
            ("Resting HR", rhrPart.score, weights.rhr, rhrPart.raw, rhrPart.base, rhrPart.est),
            ("Sleep", i.sleep?.value, weights.sleep, i.sleep?.value, nil, i.sleep?.isEstimated ?? false),
        ])
        var conf: Confidence = comps.count == 3 ? .high : (comps.count == 2 ? .medium : .low)
        if estimated { conf = min(conf, worstConf, .medium) }
        return ScoreResult(kind: .readiness, day: day, value: value.map { ($0 * 10).rounded() / 10 }, components: comps,
                           inputsUsed: used, missingInputs: missing, confidence: conf, isEstimated: estimated)
    }
}
