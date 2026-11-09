import XCTest
@testable import PulseCore

final class StreakTests: XCTestCase {
    func testSharedStreakFixtures() throws {
        let json = try Fixtures.json("streak_cases.json")
        for c in json["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let g = c["goal"] as! [String: Any]
            let goal = Goal(metric: MetricID(g["metric"] as! String), target: (g["target"] as! NSNumber).doubleValue,
                            period: GoalPeriod(rawValue: g["period"] as! String)!, direction: GoalDirection(rawValue: g["direction"] as! String)!)
            let daily = Dictionary(uniqueKeysWithValues: (c["daily"] as! [String: NSNumber]).map { (DayKey(string: $0.key)!, $0.value.doubleValue) })
            let info = Streaks.compute(goal: goal, metric: MetricRegistry.type(goal.metric)!, daily: daily, today: DayKey(string: c["today"] as! String)!)
            let e = c["expected"] as! [String: Any]
            XCTAssertEqual(info.current, e["current"] as? Int, name)
            XCTAssertEqual(info.longest, e["longest"] as? Int, name)
            XCTAssertEqual(info.metCurrentPeriod, e["metCurrentPeriod"] as? Bool, name)
            if let r = e["recent"] as? [Bool] { XCTAssertEqual(info.recent, r, name) }
        }
    }

    func testWidgetSnapshotRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try WidgetSnapshot.sample.write(to: url)
        let back = try XCTUnwrap(WidgetSnapshot.read(from: url))
        XCTAssertEqual(back.metrics.count, WidgetSnapshot.sample.metrics.count)
        XCTAssertEqual(back.metric(.steps)?.formatted, "7,432")
        XCTAssertEqual(back.score(.readiness)?.value, 78)
    }
}
