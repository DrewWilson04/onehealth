import Foundation

/// Guard-rail for App Review guideline 5.1.3(ii): only allow-listed,
/// non-health configuration keys may be written to the iCloud-synced store.
/// Anything else is refused (and kept local) so a future change can't leak
/// health data into iCloud by accident.
public enum CloudPolicy {
    public static let allowedExactKeys: Set<String> = [
        "preferences", "preferredSources", "sourcePriority", "dashboardLayout", "goalsInitialized", "widgetLayout",
    ]
    public static let allowedPrefixes: [String] = ["goal.", "meal.", "challenge."]

    /// Keys that would indicate health data and must never sync.
    public static let forbiddenFragments: [String] = ["sample", "aggregate", "score", "sleepNight", "heart", "hrv", "weight.", "food.log", "custom."]

    public static func isAllowedInCloud(_ key: String, syncGoals: Bool = true, syncMealTemplates: Bool = true) -> Bool {
        let lower = key.lowercased()
        if forbiddenFragments.contains(where: { lower.contains($0.lowercased()) }) { return false }
        if key.hasPrefix("goal.") { return syncGoals }
        if key.hasPrefix("meal.") { return syncMealTemplates }
        return allowedExactKeys.contains(key) || allowedPrefixes.contains { key.hasPrefix($0) }
    }
}
