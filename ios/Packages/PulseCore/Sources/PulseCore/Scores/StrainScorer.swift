import Foundation

public struct HRPoint: Codable, Sendable, Hashable {
    public var time: Date
    public var bpm: Double
    public init(time: Date, bpm: Double) {
        self.time = time
        self.bpm = bpm
    }
}

public enum BiologicalSex: String, Codable, Sendable { case female, male, other, unknown }

/// Physiological profile used for HR zones.
public struct HRProfile: Codable, Sendable, Hashable {
    public var maxHR: Double
    public var restingHR: Double
    public var sex: BiologicalSex

    public init(maxHR: Double, restingHR: Double, sex: BiologicalSex = .unknown) {
        self.maxHR = maxHR
        self.restingHR = restingHR
        self.sex = sex
    }

    /// HRmax: Tanaka (208 − 0.7·age) when age is known, raised to the observed
    /// max if higher but capped at +15 bpm (to ignore optical spikes); else
    /// the observed max, floored at 160 and capped at 220.
    public static func estimateMaxHR(age: Double?, observedMax: Double?) -> Double {
        if let age {
            let tanaka = 208 - 0.7 * age
            if let o = observedMax { return min(max(tanaka, o), tanaka + 15) }
            return tanaka
        }
        return min(220, max(160, observedMax ?? 190))
    }

    /// Fraction of heart-rate reserve, 0…1.
    public func hrr(_ bpm: Double) -> Double {
        ScoreMath.clamp((bpm - restingHR) / max(1, maxHR - restingHR), 0, 1)
    }

    /// Zone 1–5 by %HRR: <50, 50–60, 60–70, 70–80, 80–90, 90+ (0 = below Z1).
    public func zone(_ bpm: Double) -> Int {
        let r = hrr(bpm)
        switch r {
        case ..<0.5: return 0
        case ..<0.6: return 1
        case ..<0.7: return 2
        case ..<0.8: return 3
        case ..<0.9: return 4
        default: return 5
        }
    }
}

/// Strain / Training Load. See /docs/scores.md §Strain.
public enum StrainScorer {
    /// Intervals between HR readings longer than this are capped (the watch
    /// samples sparsely outside workouts).
    public static let maxIntervalMinutes = 5.0
    /// Ignore near-resting heart rate (below 25 % HRR) — it isn't training load.
    public static let minHRR = 0.25
    public static let acuteDays = 7
    public static let chronicDays = 28

    /// Banister TRIMP: Σ Δt[min] · HRR · k₁ · e^(k₂ · HRR), with
    /// (k₁, k₂) = (0.64, 1.92) male / unknown, (0.86, 1.67) female.
    public static func trimp(_ points: [HRPoint], profile: HRProfile) -> Double {
        let sorted = points.sorted { $0.time < $1.time }
        guard sorted.count > 1 else { return 0 }
        let (k1, k2) = profile.sex == .female ? (0.86, 1.67) : (0.64, 1.92)
        var total = 0.0
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let dt = min(maxIntervalMinutes, b.time.timeIntervalSince(a.time) / 60)
            guard dt > 0 else { continue }
            let x = profile.hrr((a.bpm + b.bpm) / 2)
            guard x >= minHRR else { continue }
            total += dt * x * k1 * exp(k2 * x)
        }
        return total
    }

    /// Minutes in each zone (1–5), for the UI and the Activity Score.
    public static func zoneMinutes(_ points: [HRPoint], profile: HRProfile) -> [Int: Double] {
        let sorted = points.sorted { $0.time < $1.time }
        var out: [Int: Double] = [:]
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let dt = min(maxIntervalMinutes, b.time.timeIntervalSince(a.time) / 60)
            let z = profile.zone((a.bpm + b.bpm) / 2)
            if z > 0 && dt > 0 { out[z, default: 0] += dt }
        }
        return out
    }

    /// 0–21 display scale: 21 · ln(1 + T/20) / ln(21), so TRIMP 400 ≈ 21.
    public static func strain(fromTRIMP t: Double) -> Double {
        ScoreMath.clamp(21 * log(1 + t / 20) / log(21), 0, 21)
    }

    public enum LoadStatus: String, Codable, Sendable {
        case undertraining, optimal, caution, highRisk, unknown
        public var title: String {
            switch self {
            case .undertraining: return "Below your usual load"
            case .optimal: return "In your optimal range"
            case .caution: return "Load is climbing"
            case .highRisk: return "Much higher than usual"
            case .unknown: return "Building your baseline"
            }
        }
    }

    public static func status(acwr: Double?) -> LoadStatus {
        guard let r = acwr else { return .unknown }
        switch r {
        case ..<0.8: return .undertraining
        case ..<1.3: return .optimal
        case ..<1.5: return .caution
        default: return .highRisk
        }
    }

    /// Acute:chronic workload ratio from daily TRIMP (days without HR data are
    /// excluded, not counted as rest). Needs ≥ 4 acute and ≥ 14 chronic days.
    public static func acwr(dailyLoad: [DayKey: Double], day: DayKey) -> (acute: Double, chronic: Double, ratio: Double)? {
        let acute = (0..<acuteDays).compactMap { dailyLoad[day.addingDays(-$0)] }
        let chronic = (0..<chronicDays).compactMap { dailyLoad[day.addingDays(-$0)] }
        guard acute.count >= 4, chronic.count >= 14 else { return nil }
        let a = ScoreMath.mean(acute), c = ScoreMath.mean(chronic)
        guard c > 0 else { return nil }
        return (a, c, a / c)
    }

    public static func score(day: DayKey, hr: [HRPoint], profile: HRProfile?, history: [DayKey: Double]) -> ScoreResult {
        guard let profile else {
            return .insufficient(.strain, day, reason: "Strain needs a resting heart rate.", missing: ["Resting HR"])
        }
        guard hr.count >= 10 else {
            return .insufficient(.strain, day, reason: "Not enough heart-rate data today.", missing: ["Heart rate"])
        }
        let t = trimp(hr, profile: profile)
        var load = history
        load[day] = t
        let ratio = acwr(dailyLoad: load, day: day)
        let st = status(acwr: ratio?.ratio)
        var extras: [String: Double] = ["trimp": t, "maxHR": profile.maxHR, "restingHR": profile.restingHR]
        if let r = ratio { extras["acute"] = r.acute; extras["chronic"] = r.chronic; extras["acwr"] = r.ratio }
        for (z, m) in zoneMinutes(hr, profile: profile) { extras["zone\(z)"] = m }
        var used = ["Heart rate (\(hr.count) readings)", "Heart-rate zones from max \(Int(profile.maxHR)) / rest \(Int(profile.restingHR)) bpm"]
        var missing: [String] = []
        if ratio != nil { used.append("28-day load history") } else { missing.append("14+ days of load history for training balance") }
        let coverage = hr.count >= 100 ? Confidence.high : (hr.count >= 40 ? .medium : .low)
        return ScoreResult(kind: .strain, day: day, value: (strain(fromTRIMP: t) * 10).rounded() / 10,
                           inputsUsed: used, missingInputs: missing, confidence: coverage,
                           reason: st == .unknown ? nil : st.title, extras: extras)
    }
}
