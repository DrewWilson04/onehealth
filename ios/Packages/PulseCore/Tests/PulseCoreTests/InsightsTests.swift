import XCTest
@testable import PulseCore

enum InsightFixture {
    static func features(_ c: [String: Any]) -> (InsightFeatures, DayKey) {
        var series: [String: [DayKey: Double]] = [:]
        for (k, v) in c["series"] as! [String: [String: NSNumber]] {
            series[k] = Dictionary(uniqueKeysWithValues: v.map { (DayKey(string: $0.key)!, $0.value.doubleValue) })
        }
        // Workouts → flags, same rule as InsightFeatures.build (late = ends ≥ 19:00).
        var late: [DayKey: Double] = [:], wd: [DayKey: Double] = [:]
        for d in (series["steps"] ?? [:]).keys { late[d] = 0; wd[d] = 0 }
        for w in c["workouts"] as! [[Any]] {
            let d = DayKey(string: w[0] as! String)!
            wd[d] = 1
            if (w[1] as! NSNumber).intValue >= 19 { late[d] = 1 }
        }
        series["lateWorkout"] = late
        series["workoutDay"] = wd
        return (InsightFeatures(series: series), DayKey(string: c["today"] as! String)!)
    }

    static func summarize(_ f: Finding) -> [String: Any] {
        var d: [String: Any] = ["id": f.id, "kind": f.kind.rawValue, "text": f.text]
        for (k, v) in f.numbers where ["effect", "r", "z", "pct", "meanA", "meanB"].contains(k) { d[k] = (v * 1000).rounded() / 1000 }
        return d
    }
}

final class InsightsTests: XCTestCase {
    func testStatisticalFunctions() {
        // t CDF: t=2.228, df=10 → 0.975 (two-sided 0.05)
        XCTAssertEqual(Stats.studentTCDF(2.228, df: 10), 0.975, accuracy: 1e-3)
        XCTAssertEqual(Stats.studentTCDF(0, df: 5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Stats.studentTCDF(1.96, df: 10_000), 0.975, accuracy: 1e-3)
        XCTAssertEqual(Stats.spearman([1, 2, 3, 4, 5], [2, 4, 6, 8, 100]), 1, accuracy: 1e-12)
        XCTAssertEqual(Stats.spearman([1, 2, 3, 4], [4, 3, 2, 1]), -1, accuracy: 1e-12)
        XCTAssertEqual(Stats.ranks([10, 20, 20, 30]), [1, 2.5, 2.5, 4])
        XCTAssertEqual(Stats.benjaminiHochberg([0.01, 0.04, 0.03, 0.5], q: 0.1), [0, 1, 2])
        XCTAssertEqual(Stats.benjaminiHochberg([0.5, 0.6], q: 0.1), [])
        let w = Stats.welch([1, 2, 3, 4, 5], [1, 2, 3, 4, 5])
        XCTAssertEqual(w.p, 1, accuracy: 1e-9)
    }

    func testSharedInsightFixtures() throws {
        let json = try Fixtures.json("insights_cases.json")
        let tol = (json["tolerance"] as? NSNumber)?.doubleValue ?? 0.01
        let record = ProcessInfo.processInfo.environment["RECORD_FIXTURES"] == "1"
        for c in json["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let (f, today) = InsightFixture.features(c)
            let findings = InsightsEngine.run(f, today: today)
            if record || c["expected"] == nil {
                let data = try JSONSerialization.data(withJSONObject: ["name": name, "expected": findings.map(InsightFixture.summarize)], options: [.sortedKeys])
                print("RECORDED_EXPECTED=" + String(data: data, encoding: .utf8)!)
                if !record { XCTFail("record \(name)") }
                continue
            }
            let expected = c["expected"] as! [[String: Any]]
            XCTAssertEqual(Set(findings.map(\.id)), Set(expected.map { $0["id"] as! String }), name)
            for e in expected {
                guard let got = findings.first(where: { $0.id == e["id"] as? String }) else { continue }
                XCTAssertEqual(got.text, e["text"] as? String, name)
                for k in ["effect", "r", "z", "pct"] {
                    if let v = e[k] as? NSNumber { XCTAssertClose(got.numbers[k], v.doubleValue, accuracy: tol, "\(name) \(k)") }
                }
            }
        }
    }

    func testSignalScenarioFindsPlantedEffects() throws {
        let json = try Fixtures.json("insights_cases.json")
        let c = (json["cases"] as! [[String: Any]])[0]
        let (f, today) = InsightFixture.features(c)
        let ids = Set(InsightsEngine.run(f, today: today).map(\.id))
        XCTAssertTrue(ids.contains("lateWorkout-hrv"), "planted −9 ms HRV after late workouts")
        XCTAssertTrue(ids.contains("steps8k-sleep"), "planted +35 min sleep after 8k days")
        XCTAssertTrue(ids.contains("anomaly-restingHeartRate"), "planted RHR spike today")
        XCTAssertTrue(ids.contains("trend-steps"), "planted step increase in last 14 days")
        let hrv = InsightsEngine.run(f, today: today).first { $0.id == "lateWorkout-hrv" }!
        XCTAssertLessThan(hrv.numbers["effect"]!, -5)
        XCTAssertTrue(hrv.text.contains("lower"))
        XCTAssertFalse(hrv.text.contains("[["), "all tokens filled")
    }

    func testNoiseScenarioHasNoFalseRelationships() throws {
        let json = try Fixtures.json("insights_cases.json")
        let c = (json["cases"] as! [[String: Any]])[1]
        let (f, today) = InsightFixture.features(c)
        let rel = InsightsEngine.run(f, today: today).filter { $0.kind == .conditional || $0.kind == .correlation }
        XCTAssertTrue(rel.isEmpty, "found spurious: \(rel.map(\.id))")
    }
}

final class InsightValidationTests: XCTestCase {
    let tokens = ["effect": "8 ms", "a": "44 ms", "b": "52 ms"]

    func testAcceptsTokenOnlyNumbers() {
        XCTAssertEqual(InsightValidation.validateAndFill("HRV dips by [[effect]] after late sessions.", tokens: tokens),
                       "HRV dips by 8 ms after late sessions.")
    }

    func testRejectsModelInventedNumbers() {
        XCTAssertNil(InsightValidation.validateAndFill("HRV dips by 10 ms.", tokens: tokens))
        XCTAssertNil(InsightValidation.validateAndFill("About [[effect]] (roughly 15%).", tokens: tokens))
    }

    func testRejectsUnknownOrBrokenTokens() {
        XCTAssertNil(InsightValidation.validateAndFill("Down [[pct]].", tokens: tokens))
        XCTAssertNil(InsightValidation.validateAndFill("Down [[effect.", tokens: tokens))
        XCTAssertNil(InsightValidation.validateAndFill("Down effect]].", tokens: tokens))
    }
}
