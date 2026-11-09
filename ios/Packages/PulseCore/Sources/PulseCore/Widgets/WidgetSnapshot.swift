import Foundation

/// Small, pre-formatted snapshot the app writes to the App Group container
/// for widgets and complications (they never query HealthKit themselves —
/// HealthKit data is unavailable to extensions while the device is locked).
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    public struct Metric: Codable, Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var value: Double?
        public var formatted: String
        public var symbol: String
        public var section: String
        public var goal: Double?
        public var progress: Double?
        public var streak: Int?
        public var week: [Double]
        public init(id: String, title: String, value: Double?, formatted: String, symbol: String, section: String,
                    goal: Double? = nil, progress: Double? = nil, streak: Int? = nil, week: [Double] = []) {
            self.id = id
            self.title = title
            self.value = value
            self.formatted = formatted
            self.symbol = symbol
            self.section = section
            self.goal = goal
            self.progress = progress
            self.streak = streak
            self.week = week
        }
    }
    public struct Score: Codable, Sendable, Hashable {
        public var kind: String
        public var value: Double?
        public var label: String
        public var isEstimated: Bool
        public init(kind: String, value: Double?, label: String, isEstimated: Bool) {
            self.kind = kind
            self.value = value
            self.label = label
            self.isEstimated = isEstimated
        }
    }
    public struct ChallengeStanding: Codable, Sendable, Hashable {
        public var title: String
        public var rank: Int
        public var participants: Int
        public var score: Double
        public init(title: String, rank: Int, participants: Int, score: Double) {
            self.title = title
            self.rank = rank
            self.participants = participants
            self.score = score
        }
    }

    public var generatedAt: Date
    public var day: DayKey
    public var isPro: Bool
    public var metrics: [Metric]
    public var rings: ActivityRings?
    public var scores: [Score]
    public var latestHeartRate: Double?
    public var challenge: ChallengeStanding?

    public init(generatedAt: Date, day: DayKey, isPro: Bool, metrics: [Metric], rings: ActivityRings?, scores: [Score],
                latestHeartRate: Double? = nil, challenge: ChallengeStanding? = nil) {
        self.generatedAt = generatedAt
        self.day = day
        self.isPro = isPro
        self.metrics = metrics
        self.rings = rings
        self.scores = scores
        self.latestHeartRate = latestHeartRate
        self.challenge = challenge
    }

    public func metric(_ id: MetricID) -> Metric? { metrics.first { $0.id == id.rawValue } }
    public func score(_ kind: ScoreKind) -> Score? { scores.first { $0.kind == kind.rawValue } }

    public static let fileName = "widget-snapshot.json"

    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(WidgetSnapshot.self, from: data)
    }

    public func write(to url: URL) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try e.encode(self).write(to: url, options: [.atomic])
    }

    /// Placeholder for widget previews / gallery.
    public static let sample = WidgetSnapshot(
        generatedAt: Date(), day: DayKey(year: 2026, month: 1, day: 1), isPro: true,
        metrics: [
            Metric(id: "steps", title: "Steps", value: 7432, formatted: "7,432", symbol: "figure.walk", section: "activity", goal: 8000, progress: 0.93, streak: 4, week: [6200, 9100, 8300, 7000, 10400, 5600, 7432]),
            Metric(id: "activeEnergy", title: "Active Energy", value: 412, formatted: "412 kcal", symbol: "flame.fill", section: "activity"),
            Metric(id: "sleep", title: "Sleep", value: 452, formatted: "7h 32m", symbol: "bed.double.fill", section: "sleep", goal: 450, progress: 1, streak: 2),
            Metric(id: "restingHeartRate", title: "Resting HR", value: 56, formatted: "56 bpm", symbol: "heart", section: "heart"),
            Metric(id: "water", title: "Water", value: 1250, formatted: "1,250 mL", symbol: "drop", section: "body", goal: 2000, progress: 0.62),
        ],
        rings: ActivityRings(move: 412, moveGoal: 500, exercise: 24, exerciseGoal: 30, stand: 9, standGoal: 12),
        scores: [Score(kind: "readiness", value: 78, label: "Good", isEstimated: false),
                 Score(kind: "sleep", value: 84, label: "Good", isEstimated: false)],
        latestHeartRate: 64,
        challenge: ChallengeStanding(title: "Weekend Warriors", rank: 2, participants: 8, score: 312))
}
