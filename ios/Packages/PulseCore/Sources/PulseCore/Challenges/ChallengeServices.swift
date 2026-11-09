import Foundation

/// Challenge catalog + membership. Implementations: `MockChallengeService`
/// (this phase, offline) and a future server-backed service. The UI depends
/// only on these protocols, so swapping in the server needs no UI changes.
public protocol ChallengeService: Sendable {
    func discover(kind: ChallengeKind?, region: String?) async throws -> [Challenge]
    func joined() async throws -> [Challenge]
    func membership(_ challengeID: String) async -> ChallengeMembership?
    func join(_ challengeID: String, shareScore: Bool) async throws
    func leave(_ challengeID: String) async throws
    func setSharing(_ challengeID: String, shareScore: Bool) async throws
    /// Requires `Feature.createCustomChallenges` (checked by the UI via EntitlementService).
    func create(_ challenge: Challenge) async throws -> Challenge
    /// Submits ONLY aggregated daily scores, and only for challenges where the
    /// user opted in to sharing.
    func submit(_ scores: [DailyChallengeScore]) async throws
}

public protocol LeaderboardService: Sendable {
    func leaderboard(for challenge: Challenge, myDaily: [DayKey: Double], today: DayKey) async throws -> [LeaderboardEntry]
}

// MARK: - TODO stubs for the server phase

/// TODO(auth): Sign in with Apple → server session; store tokens in Keychain.
public protocol AuthService: Sendable {
    var isSignedIn: Bool { get async }
    func signIn() async throws
    func signOut() async throws
}

/// TODO(server-sync): REST/WebSocket client implementing ChallengeService +
/// LeaderboardService against the challenge backend. Must:
/// - send only `DailyChallengeScore` (aggregated) for opted-in challenges
/// - include an anti-cheat attestation (App Attest / DeviceCheck)
/// - never send raw samples, sources or locations finer than city/region
/// - add NSPrivacyCollectedDataTypeFitness to PrivacyInfo.xcprivacy and
///   update the App Privacy answers + privacy policy before shipping
public final class ServerChallengeService: ChallengeService, LeaderboardService, @unchecked Sendable {
    public init() {}
    public func discover(kind: ChallengeKind?, region: String?) async throws -> [Challenge] { throw ChallengeError.notImplemented }
    public func joined() async throws -> [Challenge] { throw ChallengeError.notImplemented }
    public func membership(_ challengeID: String) async -> ChallengeMembership? { nil }
    public func join(_ challengeID: String, shareScore: Bool) async throws { throw ChallengeError.notImplemented }
    public func leave(_ challengeID: String) async throws { throw ChallengeError.notImplemented }
    public func setSharing(_ challengeID: String, shareScore: Bool) async throws { throw ChallengeError.notImplemented }
    public func create(_ challenge: Challenge) async throws -> Challenge { throw ChallengeError.notImplemented }
    public func submit(_ scores: [DailyChallengeScore]) async throws { throw ChallengeError.notImplemented }
    public func leaderboard(for challenge: Challenge, myDaily: [DayKey: Double], today: DayKey) async throws -> [LeaderboardEntry] {
        throw ChallengeError.notImplemented
    }
}

/// TODO(push): register for remote notifications (rank changes, challenge
/// start/end) once the server exists. Local notifications are fine meanwhile.
public protocol ChallengeNotificationService: Sendable {
    func scheduleReminder(for challenge: Challenge) async
}

/// TODO(anti-cheat): server-side validation will be authoritative. This
/// client-side plausibility check flags obviously impossible days before
/// they're ever submitted.
public enum AntiCheat {
    public enum Flag: String, Codable, Sendable { case implausibleSteps, implausibleActiveMinutes, manualData, estimatedData }

    public static func check(_ i: ActivityInputs, containsManual: Bool = false, containsEstimated: Bool = false) -> [Flag] {
        var f: [Flag] = []
        if (i.steps ?? 0) > 80_000 { f.append(.implausibleSteps) }
        if (i.exerciseMinutes ?? 0) > 16 * 60 { f.append(.implausibleActiveMinutes) }
        if containsManual { f.append(.manualData) }
        if containsEstimated { f.append(.estimatedData) }
        return f
    }
}

// TODO(provider-connectors): direct Fitbit / WHOOP / Garmin / Oura APIs need
// OAuth + a server-side token exchange; implement `DataProvider` for each.

public enum ChallengeError: LocalizedError {
    case notImplemented, notFound, alreadyJoined
    public var errorDescription: String? {
        switch self {
        case .notImplemented: return "Online challenges aren't available yet."
        case .notFound: return "Challenge not found."
        case .alreadyJoined: return "You've already joined this challenge."
        }
    }
}
