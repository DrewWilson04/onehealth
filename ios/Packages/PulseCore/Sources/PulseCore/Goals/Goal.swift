import Foundation

public enum GoalPeriod: String, Codable, Sendable, CaseIterable { case day, week }
public enum GoalDirection: String, Codable, Sendable, CaseIterable { case atLeast, atMost }

/// A user target for a metric. Synced via CloudKit as configuration.
/// NOTE (guideline 5.1.3 gray area): a target such as "weight ≤ 70 kg" is a
/// user preference, not a health record. Set `SettingsSync.syncGoals = false`
/// to keep goals local-only if you want zero iCloud exposure.
public struct Goal: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var metric: MetricID
    public var target: Double
    public var period: GoalPeriod
    public var direction: GoalDirection
    public var createdAt: Date

    public init(id: String = UUID().uuidString, metric: MetricID, target: Double, period: GoalPeriod = .day,
                direction: GoalDirection = .atLeast, createdAt: Date = Date()) {
        self.id = id
        self.metric = metric
        self.target = target
        self.period = period
        self.direction = direction
        self.createdAt = createdAt
    }

    public func isMet(_ value: Double?) -> Bool {
        guard let value else { return false }
        return direction == .atLeast ? value >= target : value <= target
    }

    /// 0...1+ progress (for rings). For "at most" goals progress is 1 while
    /// under target and decreases above it.
    public func progress(_ value: Double?) -> Double {
        guard let value, target > 0 else { return 0 }
        switch direction {
        case .atLeast: return value / target
        case .atMost: return value <= target ? 1 : max(0, 1 - (value - target) / target)
        }
    }

    public static let defaults: [Goal] = [
        Goal(id: "default.steps", metric: .steps, target: 8000),
        Goal(id: "default.sleep", metric: .sleep, target: 450),
        Goal(id: "default.exercise", metric: .exerciseTime, target: 30),
        Goal(id: "default.water", metric: .water, target: 2000),
    ]
}

/// Non-health user preferences (synced via CloudKit).
public struct UserPreferences: Codable, Sendable, Hashable {
    public enum UnitSystem: String, Codable, Sendable, CaseIterable { case automatic, metric, imperial }
    public var unitSystem: UnitSystem = .automatic
    public var sleepGoalMinutes: Double = 480
    /// Opt-in toggle defaults for new challenges (still asked per challenge).
    public var defaultShareChallengeScore: Bool = false
    /// Coarse region for local challenges (city/region text only).
    public var challengeRegion: String?
    public var aiInsightsEnabled: Bool = true
    public init() {}
}
