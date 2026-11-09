import Foundation

/// A personal baseline: mean and SD over the trailing window, excluding the
/// day being scored and any estimated values.
public struct Baseline: Codable, Sendable, Hashable {
    public var mean: Double
    public var sd: Double
    public var count: Int

    public static let windowDays = 30
    public static let minDays = 10

    /// - Parameter logTransform: HRV is log-normally distributed; baselines
    ///   are computed on ln(HRV).
    public static func compute(_ values: [DayKey: Double], before day: DayKey, window: Int = windowDays,
                               minDays: Int = minDays, logTransform: Bool = false) -> Baseline? {
        var xs: [Double] = []
        for k in 1...window {
            if let v = values[day.addingDays(-k)], v > 0 || !logTransform {
                xs.append(logTransform ? log(v) : v)
            }
        }
        guard xs.count >= minDays else { return nil }
        return Baseline(mean: ScoreMath.mean(xs), sd: ScoreMath.sd(xs), count: xs.count)
    }
}
