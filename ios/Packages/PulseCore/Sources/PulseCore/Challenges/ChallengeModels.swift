import Foundation

public enum ChallengeKind: String, Codable, Sendable, CaseIterable {
    case friends, local, global, custom
    public var title: String {
        switch self {
        case .friends: return "Friends"
        case .local: return "Local"
        case .global: return "Global"
        case .custom: return "Custom"
        }
    }
}

/// What a challenge ranks on. All values are computed on-device from
/// competition-eligible (measured, non-manual, non-estimated) data.
public enum ChallengeMetric: String, Codable, Sendable, CaseIterable {
    case activityScore, steps, activeMinutes, workoutMinutes, sleepTarget
    public var title: String {
        switch self {
        case .activityScore: return "Activity Score"
        case .steps: return "Steps"
        case .activeMinutes: return "Active minutes"
        case .workoutMinutes: return "Workout minutes"
        case .sleepTarget: return "Nights of 7–9 h sleep"
        }
    }

    public func dailyValue(_ i: ActivityInputs) -> Double {
        switch self {
        case .activityScore: return ActivityScore.score(i)
        case .steps: return i.steps ?? 0
        case .activeMinutes: return max(i.exerciseMinutes ?? 0, (2...5).reduce(0.0) { $0 + (i.zoneMinutes[$1] ?? 0) })
        case .workoutMinutes: return i.workoutMinutes ?? 0
        case .sleepTarget: return (i.sleepMinutes.map { $0 >= 420 && $0 <= 540 } ?? false) ? 1 : 0
        }
    }
}

public struct ChallengeRules: Codable, Sendable, Hashable {
    public enum Aggregation: String, Codable, Sendable, CaseIterable { case total, dailyAverage, bestDay }
    public var aggregation: Aggregation
    /// Optional per-day cap (e.g. max 20 000 steps/day counts).
    public var dailyCap: Double?
    public init(aggregation: Aggregation = .total, dailyCap: Double? = nil) {
        self.aggregation = aggregation
        self.dailyCap = dailyCap
    }
}

public struct Challenge: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var kind: ChallengeKind
    public var metric: ChallengeMetric
    public var start: DayKey
    public var end: DayKey
    public var rules: ChallengeRules
    /// Coarse region only ("Austin, Texas"), never coordinates.
    public var region: String?
    public var createdByMe: Bool
    public var participantCount: Int
    /// True for mock/preview challenges with seeded sample participants.
    public var isPreview: Bool

    public init(id: String = UUID().uuidString, title: String, kind: ChallengeKind, metric: ChallengeMetric, start: DayKey, end: DayKey,
                rules: ChallengeRules = ChallengeRules(), region: String? = nil, createdByMe: Bool = false,
                participantCount: Int = 0, isPreview: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.metric = metric
        self.start = start
        self.end = end
        self.rules = rules
        self.region = region
        self.createdByMe = createdByMe
        self.participantCount = participantCount
        self.isPreview = isPreview
    }

    public func isActive(on day: DayKey) -> Bool { day >= start && day <= end }
    public var lengthDays: Int { DayKey.daysBetween(start, end) + 1 }
}

/// The ONLY data that would ever leave the device for a challenge: one
/// aggregated number per day — never raw health data. Sent only when the user
/// opted in for that specific challenge.
public struct DailyChallengeScore: Codable, Sendable, Hashable {
    public var challengeID: String
    public var day: DayKey
    public var value: Double
    public init(challengeID: String, day: DayKey, value: Double) {
        self.challengeID = challengeID
        self.day = day
        self.value = value
    }
}

/// Per-user, per-challenge membership (synced via CloudKit as config).
public struct ChallengeMembership: Codable, Sendable, Hashable {
    public var challengeID: String
    public var joinedAt: Date
    /// Opt-in per challenge; defaults to false.
    public var shareScore: Bool
    public init(challengeID: String, joinedAt: Date = Date(), shareScore: Bool = false) {
        self.challengeID = challengeID
        self.joinedAt = joinedAt
        self.shareScore = shareScore
    }
}

public struct LeaderboardEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var displayName: String
    public var symbol: String
    public var score: Double
    public var rank: Int
    public var isCurrentUser: Bool
    public var isSample: Bool
}

public enum ChallengeScoring {
    /// Aggregates daily values per the challenge rules, over the days so far.
    public static func total(_ challenge: Challenge, daily: [DayKey: Double], through today: DayKey) -> Double {
        let end = min(today, challenge.end)
        guard challenge.start <= end else { return 0 }
        let vals = DayKey.range(challenge.start, through: end).compactMap { d -> Double? in
            guard let v = daily[d] else { return nil }
            return challenge.rules.dailyCap.map { min(v, $0) } ?? v
        }
        switch challenge.rules.aggregation {
        case .total: return vals.reduce(0, +)
        case .dailyAverage: return vals.isEmpty ? 0 : vals.reduce(0, +) / Double(vals.count)
        case .bestDay: return vals.max() ?? 0
        }
    }

    public static func rank(_ entries: [(id: String, name: String, symbol: String, score: Double, me: Bool, sample: Bool)]) -> [LeaderboardEntry] {
        let sorted = entries.sorted { $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score }
        var out: [LeaderboardEntry] = []
        var lastScore: Double?, lastRank = 0
        for (i, e) in sorted.enumerated() {
            let rank = (lastScore == e.score) ? lastRank : i + 1
            lastScore = e.score
            lastRank = rank
            out.append(LeaderboardEntry(id: e.id, displayName: e.name, symbol: e.symbol, score: e.score, rank: rank, isCurrentUser: e.me, isSample: e.sample))
        }
        return out
    }
}
