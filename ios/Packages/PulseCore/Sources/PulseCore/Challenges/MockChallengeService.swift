import Foundation

/// Offline challenge service with seeded, clearly-labelled sample
/// participants so the whole challenge UI works without a server.
/// Gated by the CHALLENGES_PREVIEW build flag (see README).
public actor MockChallengeService: ChallengeService, LeaderboardService {
    public struct State: Codable, Sendable {
        public var memberships: [String: ChallengeMembership] = [:]
        public var custom: [Challenge] = []
        public var submitted: [DailyChallengeScore] = []
        public init() {}
    }

    private var state: State
    private let today: @Sendable () -> DayKey
    private let persist: @Sendable (State) -> Void

    public init(state: State = State(), today: @escaping @Sendable () -> DayKey, persist: @escaping @Sendable (State) -> Void = { _ in }) {
        self.state = state
        self.today = today
        self.persist = persist
    }

    public func currentState() -> State { state }

    /// Deterministic catalog relative to today.
    public func catalog() -> [Challenge] {
        let t = today()
        let ws = t.weekStart
        return [
            Challenge(id: "preview-weekend", title: "Weekend Warriors", kind: .friends, metric: .activityScore,
                      start: ws.addingDays(4), end: ws.addingDays(6), participantCount: 8, isPreview: true),
            Challenge(id: "preview-week-steps", title: "Step It Up This Week", kind: .friends, metric: .steps,
                      start: ws, end: ws.addingDays(6), rules: ChallengeRules(aggregation: .total, dailyCap: 30_000), participantCount: 6, isPreview: true),
            Challenge(id: "preview-local", title: "City Move Month", kind: .local, metric: .activityScore,
                      start: t.monthStart, end: t.monthStart.addingDays(27), rules: ChallengeRules(aggregation: .dailyAverage),
                      region: nil, participantCount: 240, isPreview: true),
            Challenge(id: "preview-global-sleep", title: "Global Sleep Streak", kind: .global, metric: .sleepTarget,
                      start: t.addingDays(-6), end: t.addingDays(7), participantCount: 12_400, isPreview: true),
        ] + state.custom
    }

    public func discover(kind: ChallengeKind?, region: String?) async throws -> [Challenge] {
        catalog().filter { c in
            (kind == nil || c.kind == kind) && state.memberships[c.id] == nil && c.end >= today()
        }.map { c in
            var c = c
            if c.kind == .local { c.region = region ?? "Your area" }
            return c
        }
    }

    public func joined() async throws -> [Challenge] {
        catalog().filter { state.memberships[$0.id] != nil }
    }

    public func membership(_ challengeID: String) async -> ChallengeMembership? { state.memberships[challengeID] }

    public func join(_ challengeID: String, shareScore: Bool) async throws {
        guard catalog().contains(where: { $0.id == challengeID }) else { throw ChallengeError.notFound }
        state.memberships[challengeID] = ChallengeMembership(challengeID: challengeID, shareScore: shareScore)
        persist(state)
    }

    public func leave(_ challengeID: String) async throws {
        state.memberships[challengeID] = nil
        state.submitted.removeAll { $0.challengeID == challengeID }
        persist(state)
    }

    public func setSharing(_ challengeID: String, shareScore: Bool) async throws {
        guard var m = state.memberships[challengeID] else { throw ChallengeError.notFound }
        m.shareScore = shareScore
        state.memberships[challengeID] = m
        if !shareScore { state.submitted.removeAll { $0.challengeID == challengeID } }
        persist(state)
    }

    public func create(_ challenge: Challenge) async throws -> Challenge {
        var c = challenge
        c.kind = .custom
        c.createdByMe = true
        c.isPreview = true
        c.participantCount = 5
        state.custom.append(c)
        state.memberships[c.id] = ChallengeMembership(challengeID: c.id, shareScore: false)
        persist(state)
        return c
    }

    public func submit(_ scores: [DailyChallengeScore]) async throws {
        // Only opted-in challenges; replace same-day values.
        for s in scores where state.memberships[s.challengeID]?.shareScore == true {
            state.submitted.removeAll { $0.challengeID == s.challengeID && $0.day == s.day }
            state.submitted.append(s)
        }
        persist(state)
    }

    public func leaderboard(for challenge: Challenge, myDaily: [DayKey: Double], today: DayKey) async throws -> [LeaderboardEntry] {
        let me = ChallengeScoring.total(challenge, daily: myDaily, through: today)
        var entries: [(id: String, name: String, symbol: String, score: Double, me: Bool, sample: Bool)] = []
        for p in Self.seededParticipants(challenge, count: min(challenge.participantCount - 1, 24), today: today) {
            entries.append((p.id, p.name, p.symbol, p.score, false, true))
        }
        entries.append(("me", "You", "person.crop.circle.fill", me, true, false))
        return ChallengeScoring.rank(entries)
    }

    static let names = ["Alex", "Sam", "Jordan", "Taylor", "Riley", "Casey", "Morgan", "Jamie", "Avery", "Quinn", "Drew", "Rowan",
                        "Sky", "Reese", "Parker", "Emerson", "Hayden", "Kai", "Logan", "Elliot", "Finley", "Harper", "Remy", "Sage"]
    static let symbols = ["figure.run", "figure.walk", "bicycle", "figure.hiking", "figure.yoga", "figure.pool.swim"]

    /// Deterministic sample participants (seeded by challenge id).
    public static func seededParticipants(_ c: Challenge, count: Int, today: DayKey) -> [(id: String, name: String, symbol: String, score: Double)] {
        var seed: UInt64 = 1469598103934665603
        for b in c.id.utf8 { seed = (seed ^ UInt64(b)) &* 1099511628211 }
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        let days = Double(max(0, min(DayKey.daysBetween(c.start, min(today, c.end)) + 1, c.lengthDays)))
        let perDayTypical: Double
        switch c.metric {
        case .activityScore: perDayTypical = 55
        case .steps: perDayTypical = 8500
        case .activeMinutes: perDayTypical = 40
        case .workoutMinutes: perDayTypical = 35
        case .sleepTarget: perDayTypical = 0.6
        }
        return (0..<max(0, count)).map { i in
            let skill = 0.55 + next() * 0.9  // 0.55–1.45 × typical
            var daily = perDayTypical * skill
            if let cap = c.rules.dailyCap { daily = min(daily, cap) }
            let score: Double
            switch c.rules.aggregation {
            case .total: score = c.metric == .sleepTarget ? (days * min(1, skill * 0.7)).rounded() : (daily * days).rounded()
            case .dailyAverage, .bestDay: score = (daily * 10).rounded() / 10
            }
            return ("sample-\(i)", "\(names[i % names.count]) (sample)", symbols[i % symbols.count], score)
        }
    }
}
