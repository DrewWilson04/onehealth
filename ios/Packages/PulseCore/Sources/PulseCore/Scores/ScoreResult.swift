import Foundation

/// One input's contribution to a score.
public struct ScoreComponent: Codable, Sendable, Hashable {
    public var name: String
    /// 0–100 sub-score.
    public var score: Double
    /// Effective weight after renormalization (sums to 1 across components).
    public var weight: Double
    /// Raw measured value (e.g. 52 ms) and its baseline (e.g. 48 ms), if any.
    public var raw: Double?
    public var baseline: Double?
    public var isEstimated: Bool

    public init(name: String, score: Double, weight: Double, raw: Double? = nil, baseline: Double? = nil, isEstimated: Bool = false) {
        self.name = name
        self.score = score
        self.weight = weight
        self.raw = raw
        self.baseline = baseline
        self.isEstimated = isEstimated
    }
}

/// Result of a derived score for a day. `value == nil` means "not enough
/// data" — we never guess when key inputs are missing.
public struct ScoreResult: Codable, Sendable, Hashable {
    public var kind: ScoreKind
    public var day: DayKey
    public var value: Double?
    public var components: [ScoreComponent]
    public var inputsUsed: [String]
    public var missingInputs: [String]
    public var confidence: Confidence
    /// True if any input was gap-filled.
    public var isEstimated: Bool
    /// Why the score is unavailable, or a caveat.
    public var reason: String?
    /// Kind-specific extras (strain: trimp, acwr, acute, chronic; energy: series).
    public var extras: [String: Double]
    public var series: [Double]?

    public init(kind: ScoreKind, day: DayKey, value: Double?, components: [ScoreComponent] = [], inputsUsed: [String] = [],
                missingInputs: [String] = [], confidence: Confidence = .low, isEstimated: Bool = false, reason: String? = nil,
                extras: [String: Double] = [:], series: [Double]? = nil) {
        self.kind = kind
        self.day = day
        self.value = value
        self.components = components
        self.inputsUsed = inputsUsed
        self.missingInputs = missingInputs
        self.confidence = confidence
        self.isEstimated = isEstimated
        self.reason = reason
        self.extras = extras
        self.series = series
    }

    public static func insufficient(_ kind: ScoreKind, _ day: DayKey, reason: String, missing: [String], used: [String] = []) -> ScoreResult {
        ScoreResult(kind: kind, day: day, value: nil, inputsUsed: used, missingInputs: missing, confidence: .low, reason: reason)
    }

    /// Qualitative label shown next to the number.
    public var label: String {
        guard let v = value else { return "Not enough data" }
        switch kind {
        case .strain:
            switch v { case ..<8: return "Light"; case ..<14: return "Moderate"; case ..<18: return "High"; default: return "All out" }
        default:
            switch v { case ..<34: return "Low"; case ..<67: return "Fair"; case ..<85: return "Good"; default: return "Excellent" }
        }
    }
}

enum ScoreMath {
    static func logistic(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
    static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 100) -> Double { min(hi, max(lo, x)) }

    /// Weighted mean with renormalization over present components.
    static func combine(_ parts: [(name: String, score: Double?, weight: Double, raw: Double?, baseline: Double?, est: Bool)]) -> (Double?, [ScoreComponent]) {
        let present = parts.filter { $0.score != nil }
        let total = present.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return (nil, []) }
        let comps = present.map { ScoreComponent(name: $0.name, score: $0.score!, weight: $0.weight / total, raw: $0.raw, baseline: $0.baseline, isEstimated: $0.est) }
        return (comps.reduce(0) { $0 + $1.score * $1.weight }, comps)
    }

    static func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    static func sd(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return 0 }
        let m = mean(xs)
        return sqrt(xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1))
    }
}
