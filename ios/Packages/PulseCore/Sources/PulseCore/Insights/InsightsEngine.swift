import Foundation

/// A statistically supported observation. All numbers shown to the user come
/// from here — the language model (when available) only rephrases.
public struct Finding: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case conditional, correlation, anomaly, trendChange }

    public var id: String
    public var kind: Kind
    /// Outcome metric / feature (e.g. "hrv", "sleepMinutes").
    public var outcome: String
    /// Driver feature or condition (e.g. "lateWorkout", "steps≥8000").
    public var driver: String?
    /// Deterministic template with [[token]] placeholders.
    public var template: String
    /// Pre-formatted values for each token (e.g. "effect": "8 ms").
    public var values: [String: String]
    /// Raw numbers (for sorting, charts and the web parity test).
    public var numbers: [String: Double]
    public var pValue: Double?
    public var n: Int
    /// 0–1 strength used for ranking.
    public var strength: Double
    public var day: DayKey

    /// Template with tokens replaced by the engine's formatted numbers.
    public var text: String { Self.fill(template, values) }

    public static func fill(_ template: String, _ values: [String: String]) -> String {
        var s = template
        for (k, v) in values { s = s.replacingOccurrences(of: "[[\(k)]]", with: v) }
        return s
    }
}

/// Daily features for the insights engine, keyed by day. Night-based
/// features (sleep, bedtime) are keyed by the wake day.
public struct InsightFeatures: Sendable {
    public var series: [String: [DayKey: Double]]
    public init(series: [String: [DayKey: Double]]) { self.series = series }

    public static func build(daily: [MetricID: [DayKey: Double]], nights: [SleepNight], workouts: [Sample],
                             scores: [ScoreKind: [DayKey: Double]], calendar: Calendar) -> InsightFeatures {
        var s: [String: [DayKey: Double]] = [:]
        for (k, v) in daily { s[k.rawValue] = v }
        var sleep: [DayKey: Double] = [:], bedtime: [DayKey: Double] = [:]
        for n in nights where !n.isEstimated {
            sleep[n.day] = n.asleepMinutes
            let c = calendar.dateComponents([.hour, .minute], from: n.sleepOnset)
            let minutesAfter18 = (Double((c.hour ?? 0) + 24 - 18).truncatingRemainder(dividingBy: 24)) * 60 + Double(c.minute ?? 0)
            bedtime[n.day] = minutesAfter18
        }
        s["sleepMinutes"] = sleep
        s["bedtimeAfter18"] = bedtime
        // Workout flags exist for every day that has step data (i.e. the
        // device was worn), so "no workout" days are real zeros.
        let worn = Set((daily[.steps] ?? [:]).keys)
        var late: [DayKey: Double] = [:], wd: [DayKey: Double] = [:]
        for d in worn { late[d] = 0; wd[d] = 0 }
        for w in workouts where !w.isEstimated {
            let d = DayKey(w.start, calendar: calendar)
            wd[d] = 1
            if calendar.component(.hour, from: w.end) >= 19 { late[d] = 1 }
        }
        s["workoutDay"] = wd
        s["lateWorkout"] = late
        var weekend: [DayKey: Double] = [:]
        for d in worn.union(sleep.keys) { weekend[d] = d.isoWeekday >= 6 ? 1 : 0 }
        s["weekend"] = weekend
        for (k, v) in scores { s["score.\(k.rawValue)"] = v }
        return InsightFeatures(series: s)
    }
}

public enum InsightsEngine {
    public struct Config: Sendable {
        public var lookbackDays = 90
        public var minGroup = 7
        public var minPairs = 21
        public var fdr = 0.10
        public var minAbsCorrelation = 0.30
        public var anomalyZ = 2.5
        public var anomalyBaselineDays = 30
        public var anomalyMinDays = 14
        public var trendRecentDays = 14
        public var trendPriorDays = 28
        public var trendMinPct = 0.05
        public var trendP = 0.01
        public init() {}
    }

    struct Conditional {
        let id: String
        let driver: String
        let threshold: Double  // driver ≥ threshold → group A
        let outcome: String
        let lag: Int           // outcome day = driver day + lag
        let minEffect: Double  // practical significance, outcome units
        let template: String   // tokens: effect, a, b, nA, nB
        let higherWord: String
        let lowerWord: String
    }

    /// Curated hypotheses (a short list keeps multiple-comparison risk low;
    /// Benjamini–Hochberg controls the false discovery rate across them).
    static let conditionals: [Conditional] = [
        Conditional(id: "lateWorkout-hrv", driver: "lateWorkout", threshold: 1, outcome: "hrv", lag: 1, minEffect: 2,
                    template: "Your HRV is [[effect]] [[direction]] the morning after late workouts (after 7 pm) — [[a]] vs [[b]] on other days.",
                    higherWord: "higher", lowerWord: "lower"),
        Conditional(id: "steps8k-sleep", driver: "steps", threshold: 8000, outcome: "sleepMinutes", lag: 1, minEffect: 10,
                    template: "You sleep [[effect]] [[direction]] after days with 8,000+ steps — [[a]] vs [[b]].",
                    higherWord: "longer", lowerWord: "shorter"),
        Conditional(id: "workout-sleep", driver: "workoutDay", threshold: 1, outcome: "sleepMinutes", lag: 1, minEffect: 10,
                    template: "On nights after a workout you sleep [[effect]] [[direction]] — [[a]] vs [[b]].",
                    higherWord: "longer", lowerWord: "shorter"),
        Conditional(id: "caffeine-sleep", driver: "caffeine", threshold: 200, outcome: "sleepMinutes", lag: 1, minEffect: 10,
                    template: "After days with 200 mg+ caffeine you sleep [[effect]] [[direction]] — [[a]] vs [[b]].",
                    higherWord: "longer", lowerWord: "shorter"),
        Conditional(id: "weekend-sleep", driver: "weekend", threshold: 1, outcome: "sleepMinutes", lag: 0, minEffect: 15,
                    template: "You sleep [[effect]] [[direction]] on weekends — [[a]] vs [[b]] on weekdays.",
                    higherWord: "longer", lowerWord: "shorter"),
        Conditional(id: "lateBed-readiness", driver: "bedtimeAfter18", threshold: 360, outcome: "score.readiness", lag: 0, minEffect: 3,
                    template: "Readiness is [[effect]] [[direction]] after nights you fall asleep past midnight — [[a]] vs [[b]].",
                    higherWord: "higher", lowerWord: "lower"),
    ]

    struct Correlation {
        let id: String, x: String, y: String, lag: Int, template: String
    }
    static let correlations: [Correlation] = [
        Correlation(id: "sleep-rhr", x: "sleepMinutes", y: "restingHeartRate", lag: 0,
                    template: "More sleep tends to go with a [[direction]] resting heart rate (correlation [[r]] over [[n]] days)."),
        Correlation(id: "sleep-hrv", x: "sleepMinutes", y: "hrv", lag: 0,
                    template: "More sleep tends to go with [[direction]] HRV (correlation [[r]] over [[n]] days)."),
        Correlation(id: "exercise-readiness", x: "exerciseTime", y: "score.readiness", lag: 1,
                    template: "More exercise minutes tend to be followed by [[direction]] readiness the next day (correlation [[r]] over [[n]] days)."),
    ]

    static let anomalyMetrics: [(String, Int)] = [  // (feature, direction that is notable: +1 high, -1 low, 0 both)
        ("restingHeartRate", 1), ("hrv", -1), ("sleepMinutes", -1), ("respiratoryRate", 1), ("wristTemperature", 0), ("steps", 0),
    ]
    static let trendMetrics = ["steps", "sleepMinutes", "restingHeartRate", "hrv", "bodyMass", "vo2Max", "activeEnergy", "exerciseTime"]

    public static func run(_ f: InsightFeatures, today: DayKey, config: Config = Config()) -> [Finding] {
        let from = today.addingDays(-config.lookbackDays)
        func series(_ k: String) -> [DayKey: Double] { (f.series[k] ?? [:]).filter { $0.key >= from && $0.key <= today } }

        var candidates: [(Finding, Double)] = []  // (finding, p)

        // Conditional mean differences
        for c in conditionals {
            let drv = series(c.driver), out = series(c.outcome)
            var a: [Double] = [], b: [Double] = []
            for (d, x) in drv {
                guard let y = out[d.addingDays(c.lag)] else { continue }
                if x >= c.threshold { a.append(y) } else { b.append(y) }
            }
            guard a.count >= config.minGroup, b.count >= config.minGroup else { continue }
            let w = Stats.welch(a, b)
            let ma = Stats.mean(a), mb = Stats.mean(b)
            let effect = ma - mb
            guard abs(effect) >= c.minEffect else { continue }
            let fmt = { (v: Double) in FormatToken.value(v, feature: c.outcome) }
            let finding = Finding(
                id: c.id, kind: .conditional, outcome: c.outcome, driver: c.driver, template: c.template,
                values: ["effect": fmt(abs(effect)), "direction": effect >= 0 ? c.higherWord : c.lowerWord,
                         "a": fmt(ma), "b": fmt(mb), "nA": "\(a.count)", "nB": "\(b.count)"],
                numbers: ["effect": effect, "meanA": ma, "meanB": mb, "nA": Double(a.count), "nB": Double(b.count), "p": w.p],
                pValue: w.p, n: a.count + b.count,
                strength: min(1, abs(w.t) / 6), day: today)
            candidates.append((finding, w.p))
        }

        // Correlations (Spearman)
        for c in correlations {
            let xs = series(c.x), ys = series(c.y)
            var x: [Double] = [], y: [Double] = []
            for (d, v) in xs.sorted(by: { $0.key < $1.key }) {
                if let w = ys[d.addingDays(c.lag)] { x.append(v); y.append(w) }
            }
            guard x.count >= config.minPairs else { continue }
            let r = Stats.spearman(x, y)
            guard r.isFinite, abs(r) >= config.minAbsCorrelation else { continue }
            let p = Stats.correlationPValue(r: r, n: x.count)
            let dir: String
            switch c.y {
            case "restingHeartRate": dir = r < 0 ? "lower" : "higher"
            default: dir = r > 0 ? "higher" : "lower"
            }
            let finding = Finding(id: c.id, kind: .correlation, outcome: c.y, driver: c.x, template: c.template,
                                  values: ["r": String(format: "%.2f", r), "n": "\(x.count)", "direction": dir],
                                  numbers: ["r": r, "n": Double(x.count), "p": p], pValue: p, n: x.count,
                                  strength: abs(r), day: today)
            candidates.append((finding, p))
        }

        // FDR control across all hypothesis tests.
        let keep = Stats.benjaminiHochberg(candidates.map(\.1), q: config.fdr)
        var findings = candidates.enumerated().filter { keep.contains($0.offset) }.map(\.element.0)

        // Anomalies: latest value vs trailing baseline.
        for (k, dirWanted) in anomalyMetrics {
            let s = f.series[k] ?? [:]
            guard let v = s[today] else { continue }
            let base = (1...config.anomalyBaselineDays).compactMap { s[today.addingDays(-$0)] }
            guard base.count >= config.anomalyMinDays else { continue }
            let m = Stats.mean(base), sd = Stats.sd(base)
            guard sd > 0 else { continue }
            let z = (v - m) / sd
            guard abs(z) >= config.anomalyZ, dirWanted == 0 || (z > 0) == (dirWanted > 0) else { continue }
            let fmt = { (x: Double) in FormatToken.value(x, feature: k) }
            findings.append(Finding(
                id: "anomaly-\(k)", kind: .anomaly, outcome: k, driver: nil,
                template: "Today's [[metric]] ([[value]]) is unusually [[direction]] compared with your 30-day average of [[baseline]].",
                values: ["metric": FormatToken.name(k), "value": fmt(v), "baseline": fmt(m), "direction": z > 0 ? "high" : "low"],
                numbers: ["value": v, "baseline": m, "z": z], pValue: nil, n: base.count,
                strength: min(1, abs(z) / 4), day: today))
        }

        // Trend changes: last 14 days vs the 28 before.
        for k in trendMetrics {
            let s = f.series[k] ?? [:]
            let recent = (0..<config.trendRecentDays).compactMap { s[today.addingDays(-$0)] }
            let prior = (config.trendRecentDays..<(config.trendRecentDays + config.trendPriorDays)).compactMap { s[today.addingDays(-$0)] }
            guard recent.count >= 10, prior.count >= 14 else { continue }
            let w = Stats.welch(recent, prior)
            let mr = Stats.mean(recent), mp = Stats.mean(prior)
            guard mp != 0 else { continue }
            let pct = (mr - mp) / abs(mp)
            guard w.p < config.trendP, abs(pct) >= config.trendMinPct else { continue }
            let fmt = { (x: Double) in FormatToken.value(x, feature: k) }
            findings.append(Finding(
                id: "trend-\(k)", kind: .trendChange, outcome: k, driver: nil,
                template: "Your [[metric]] has [[direction]] [[pct]] over the last two weeks — [[recent]] vs [[prior]] before.",
                values: ["metric": FormatToken.name(k), "direction": pct > 0 ? "risen" : "dropped",
                         "pct": "\(Int((abs(pct) * 100).rounded()))%", "recent": fmt(mr), "prior": fmt(mp)],
                numbers: ["recent": mr, "prior": mp, "pct": pct, "p": w.p], pValue: w.p, n: recent.count + prior.count,
                strength: min(1, abs(w.t) / 6), day: today))
        }
        return findings.sorted { ($0.strength, $0.id) > ($1.strength, $1.id) }
    }
}

/// Number formatting for insight tokens (locale-neutral so iOS and web match).
public enum FormatToken {
    public static func name(_ feature: String) -> String {
        switch feature {
        case "sleepMinutes": return "sleep"
        case "restingHeartRate": return "resting heart rate"
        case "hrv": return "HRV"
        case "respiratoryRate": return "respiratory rate"
        case "wristTemperature": return "wrist temperature"
        case "bodyMass": return "weight"
        case "vo2Max": return "cardio fitness"
        case "activeEnergy": return "active energy"
        case "exerciseTime": return "exercise minutes"
        case "score.readiness": return "readiness"
        case "steps": return "step count"
        default: return MetricRegistry.type(MetricID(feature))?.displayName.lowercased() ?? feature
        }
    }

    public static func value(_ v: Double, feature: String) -> String {
        switch feature {
        case "sleepMinutes":
            let m = Int(abs(v).rounded())
            return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
        case "hrv": return "\(Int(v.rounded())) ms"
        case "restingHeartRate", "heartRate": return "\(Int(v.rounded())) bpm"
        case "respiratoryRate": return String(format: "%.1f breaths/min", v)
        case "wristTemperature": return String(format: "%.1f °C", v)
        case "bodyMass": return String(format: "%.1f kg", v)
        case "vo2Max": return String(format: "%.1f", v)
        case "activeEnergy": return "\(Int(v.rounded())) kcal"
        case "exerciseTime": return "\(Int(v.rounded())) min"
        case "steps": return "\(grouped(Int(v.rounded()))) steps"
        case "score.readiness": return "\(Int(v.rounded())) points"
        default: return String(format: "%.1f", v)
        }
    }

    /// 12345 → "12,345" (fixed separator so iOS and web match exactly).
    public static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}
