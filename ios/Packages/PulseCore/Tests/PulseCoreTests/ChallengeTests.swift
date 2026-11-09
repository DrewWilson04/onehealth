import XCTest
@testable import PulseCore

final class ChallengeTests: XCTestCase {
    func testActivityScoreFixtures() throws {
        let json = try Fixtures.json("activity_score_cases.json")
        for c in json["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let i = c["inputs"] as! [String: Any]
            let zones = Dictionary(uniqueKeysWithValues: ((i["zoneMinutes"] as? [String: NSNumber]) ?? [:]).map { (Int($0.key)!, $0.value.doubleValue) })
            let inputs = ActivityInputs(steps: (i["steps"] as? NSNumber)?.doubleValue, exerciseMinutes: (i["exerciseMinutes"] as? NSNumber)?.doubleValue,
                                        zoneMinutes: zones, workoutMinutes: (i["workoutMinutes"] as? NSNumber)?.doubleValue,
                                        sleepMinutes: (i["sleepMinutes"] as? NSNumber)?.doubleValue)
            let b = ActivityScore.breakdown(inputs)
            let e = c["expected"] as! [String: NSNumber]
            XCTAssertEqual(b.steps, e["steps"]!.doubleValue, accuracy: 0.01, name)
            XCTAssertEqual(b.activeMinutes, e["activeMinutes"]!.doubleValue, accuracy: 0.01, name)
            XCTAssertEqual(b.intensity, e["intensity"]!.doubleValue, accuracy: 0.01, name)
            XCTAssertEqual(b.sleep, e["sleep"]!.doubleValue, accuracy: 0.01, name)
            XCTAssertEqual(ActivityScore.score(inputs), e["total"]!.doubleValue, accuracy: 0.01, name)
        }
    }

    func testManualAndEstimatedExcluded() {
        let cal = Calendar.pulse(TimeZone(identifier: "UTC")!)
        let day = DayKey(year: 2024, month: 3, day: 10)
        let src = SourceRef(bundleId: "com.apple.health.1", name: "Apple Watch")
        let t = Fixtures.iso("2024-03-10T10:00:00Z")
        let samples = [
            Sample(id: "a", type: .steps, value: 5000, unit: .count, start: t, end: t.addingTimeInterval(3600), source: src),
            Sample(id: "m", type: .steps, value: 20000, unit: .count, start: t.addingTimeInterval(7200), end: t.addingTimeInterval(7300),
                   source: SourceRef(bundleId: "com.apple.Health", name: "Health"), isManual: true),
            Sample(id: "e", type: .steps, value: 3000, unit: .count, start: t.addingTimeInterval(9000), end: t.addingTimeInterval(9600),
                   source: src, isEstimated: true),
            Sample(id: "w", type: .workout, value: 45, unit: .minute, start: t, end: t.addingTimeInterval(2700), source: src, isManual: true),
        ]
        let i = ActivityInputs.from(samples: samples, nights: [], zoneMinutes: [:], day: day, calendar: cal)
        XCTAssertEqual(i.steps, 5000, "manual and estimated steps excluded")
        XCTAssertNil(i.workoutMinutes, "manual workout excluded")
        XCTAssertEqual(AntiCheat.check(ActivityInputs(steps: 100_000)), [.implausibleSteps])
    }

    func testScoringRulesAndRanking() {
        let start = DayKey(year: 2024, month: 3, day: 4)
        var c = Challenge(id: "c", title: "t", kind: .friends, metric: .steps, start: start, end: start.addingDays(6),
                          rules: ChallengeRules(aggregation: .total, dailyCap: 20_000))
        let daily: [DayKey: Double] = [start: 10_000, start.addingDays(1): 50_000, start.addingDays(8): 9_999]
        XCTAssertEqual(ChallengeScoring.total(c, daily: daily, through: start.addingDays(10)), 30_000, "cap + outside window ignored")
        c.rules.aggregation = .dailyAverage
        XCTAssertEqual(ChallengeScoring.total(c, daily: daily, through: start.addingDays(10)), 15_000)
        c.rules.aggregation = .bestDay
        XCTAssertEqual(ChallengeScoring.total(c, daily: daily, through: start), 10_000, "only days so far")
        let ranked = ChallengeScoring.rank([("a", "A", "", 10, false, true), ("b", "B", "", 20, false, true), ("me", "You", "", 10, true, false)])
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 2], "ties share a rank")
        XCTAssertEqual(ranked[0].id, "b")
    }

    func testMockServiceOptInSharingAndDeterministicParticipants() async throws {
        let today = DayKey(year: 2024, month: 3, day: 13)
        let svc = MockChallengeService(today: { today })
        let found = try await svc.discover(kind: nil, region: "Austin, Texas")
        XCTAssertFalse(found.isEmpty)
        XCTAssertTrue(found.allSatisfy(\.isPreview), "mock challenges are labelled as previews")
        XCTAssertEqual(found.first { $0.kind == .local }?.region, "Austin, Texas")
        let ch = found.first { $0.id == "preview-week-steps" }!
        try await svc.join(ch.id, shareScore: false)
        try await svc.submit([DailyChallengeScore(challengeID: ch.id, day: today, value: 100)])
        let s1 = await svc.currentState()
        XCTAssertTrue(s1.submitted.isEmpty, "nothing submitted without opt-in")
        try await svc.setSharing(ch.id, shareScore: true)
        try await svc.submit([DailyChallengeScore(challengeID: ch.id, day: today, value: 100)])
        let s2 = await svc.currentState()
        XCTAssertEqual(s2.submitted.count, 1)
        let lb1 = try await svc.leaderboard(for: ch, myDaily: [today: 9000], today: today)
        let lb2 = try await svc.leaderboard(for: ch, myDaily: [today: 9000], today: today)
        XCTAssertEqual(lb1, lb2, "seeded participants are deterministic")
        XCTAssertEqual(lb1.filter(\.isCurrentUser).count, 1)
        XCTAssertTrue(lb1.filter { !$0.isCurrentUser }.allSatisfy { $0.isSample && $0.displayName.contains("sample") })
        let server = ServerChallengeService()
        do { _ = try await server.joined(); XCTFail("stub") } catch {}
    }
}
