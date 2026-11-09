import XCTest
@testable import PulseCore

/// Loads a scores fixture case into ScoreInputs (same procedure as web).
enum ScoreFixture {
    static func inputs(_ c: [String: Any]) -> ScoreInputs {
        let tz = TimeZone(identifier: c["timeZone"] as! String)!
        let cal = Calendar.pulse(tz)
        let day = DayKey(string: c["day"] as! String)!
        func dayMap(_ any: Any?) -> [DayKey: Double] {
            Dictionary(uniqueKeysWithValues: ((any as? [String: NSNumber]) ?? [:]).map { (DayKey(string: $0.key)!, $0.value.doubleValue) })
        }
        let hrv = ((c["hrv"] as? [String: Any]) ?? [:]).mapValues(dayMap)
        let src = SourceRef(bundleId: "com.apple.health.watch", name: "Apple Watch")
        let sleepSamples = ((c["sleepSamples"] as? [[Any]]) ?? []).enumerated().map { i, s in
            Sample(id: "s\(i)", type: .sleep, value: (s[2] as! NSNumber).doubleValue, unit: .stageCode,
                   start: Fixtures.iso(s[0] as! String), end: Fixtures.iso(s[1] as! String), source: src)
        }
        let nights = Dictionary(SleepMerger.nights(sleepSamples, priority: .default, calendar: cal).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let hr = ((c["heartRate"] as? [[Any]]) ?? []).map { HRPoint(time: Fixtures.iso($0[0] as! String), bpm: ($0[1] as! NSNumber).doubleValue) }
        let steps = ((c["steps"] as? [[Any]]) ?? []).map { (Fixtures.iso($0[0] as! String), ($0[1] as! NSNumber).doubleValue) }
        let workouts = ((c["workouts"] as? [[String]]) ?? []).map { DateInterval(start: Fixtures.iso($0[0]), end: Fixtures.iso($0[1])) }
        return ScoreInputs(day: day, calendar: cal, hrvBySource: hrv, restingHR: dayMap(c["restingHR"]), nights: nights,
                           sleepGoalMinutes: (c["sleepGoalMinutes"] as? NSNumber)?.doubleValue ?? 480,
                           heartRate: hr, steps: steps, workouts: workouts, loadHistory: dayMap(c["loadHistory"]),
                           age: (c["age"] as? NSNumber)?.doubleValue, sex: BiologicalSex(rawValue: c["sex"] as? String ?? "") ?? .unknown,
                           observedMaxHR: (c["observedMaxHR"] as? NSNumber)?.doubleValue, now: Fixtures.iso(c["now"] as! String))
    }

    static func summarize(_ r: ScoreResult) -> [String: Any] {
        var d: [String: Any] = ["confidence": r.confidence.rawValue, "isEstimated": r.isEstimated,
                                "components": r.components.map(\.name)]
        d["value"] = r.value.map { ($0 * 100).rounded() / 100 } ?? NSNull()
        for k in ["trimp", "acwr", "start"] { if let v = r.extras[k] { d[k] = (v * 100).rounded() / 100 } }
        return d
    }
}

final class ScoreFixtureTests: XCTestCase {
    func testSharedScoreFixtures() throws {
        let json = try Fixtures.json("scores_cases.json")
        let tol = (json["tolerance"] as? NSNumber)?.doubleValue ?? 0.05
        let record = ProcessInfo.processInfo.environment["RECORD_FIXTURES"] == "1"
        for c in json["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let results = ScoreEngine.computeAll(ScoreFixture.inputs(c))
            if record || c["expected"] == nil {
                var exp: [String: Any] = [:]
                for (k, r) in results { exp[k.rawValue] = ScoreFixture.summarize(r) }
                let data = try JSONSerialization.data(withJSONObject: ["name": name, "expected": exp], options: [.sortedKeys])
                print("RECORDED_EXPECTED=" + String(data: data, encoding: .utf8)!)
                if !record { XCTFail("No expected values for \(name); run with RECORD_FIXTURES=1") }
                continue
            }
            let expected = c["expected"] as! [String: [String: Any]]
            for (kind, e) in expected {
                let r = try XCTUnwrap(results[ScoreKind(rawValue: kind)!], "\(name) \(kind)")
                if let v = e["value"] as? NSNumber {
                    XCTAssertClose(r.value, v.doubleValue, accuracy: tol, "\(name) \(kind)")
                } else {
                    XCTAssertNil(r.value, "\(name) \(kind) should be not-enough-data")
                }
                XCTAssertEqual(r.confidence.rawValue, e["confidence"] as? String, "\(name) \(kind) confidence")
                XCTAssertEqual(r.isEstimated, e["isEstimated"] as? Bool, "\(name) \(kind) estimated")
                XCTAssertEqual(r.components.map(\.name), e["components"] as? [String], "\(name) \(kind) components")
                for k in ["trimp", "acwr", "start"] {
                    if let ev = e[k] as? NSNumber { XCTAssertClose(r.extras[k], ev.doubleValue, accuracy: tol, "\(name) \(kind) \(k)") }
                }
            }
        }
    }
}

final class ScoreBehaviourTests: XCTestCase {
    let cal = Calendar.pulse(TimeZone(identifier: "UTC")!)
    let day = DayKey(year: 2024, month: 3, day: 20)

    func baselineSeries(_ v: Double, jitter: Double, days: Int = 30) -> [DayKey: Double] {
        Dictionary(uniqueKeysWithValues: (1...days).map { (day.addingDays(-$0), v + ($0 % 2 == 0 ? jitter : -jitter)) })
    }

    func testReadinessMonotonicInHRVAndRHR() {
        var lastHRV = -1.0
        for todayHRV in stride(from: 30.0, through: 80, by: 10) {
            var h = baselineSeries(50, jitter: 3); h[day] = todayHRV
            var r = baselineSeries(56, jitter: 1); r[day] = 56
            let v = ReadinessScorer.score(day: day, .init(hrv: h, rhr: r, sleep: nil)).value!
            XCTAssertGreaterThan(v, lastHRV, "higher HRV → higher readiness")
            lastHRV = v
        }
        var lastRHR = 101.0
        for todayRHR in stride(from: 50.0, through: 62, by: 3) {
            var h = baselineSeries(50, jitter: 3); h[day] = 50
            var r = baselineSeries(56, jitter: 1); r[day] = todayRHR
            let v = ReadinessScorer.score(day: day, .init(hrv: h, rhr: r, sleep: nil)).value!
            XCTAssertLessThan(v, lastRHR, "higher RHR → lower readiness")
            lastRHR = v
        }
    }

    func testReadinessNotEnoughData() {
        let r = ReadinessScorer.score(day: day, .init(hrv: baselineSeries(50, jitter: 2, days: 5), rhr: [:], sleep: nil))
        XCTAssertNil(r.value)
        XCTAssertNotNil(r.reason)
        XCTAssertFalse(r.missingInputs.isEmpty)
    }

    func testReadinessRenormalizesWeights() {
        var h = baselineSeries(50, jitter: 3); h[day] = 50
        let r = ReadinessScorer.score(day: day, .init(hrv: h, rhr: [:], sleep: nil))
        XCTAssertEqual(r.components.count, 1)
        XCTAssertEqual(r.components[0].weight, 1, accuracy: 1e-9)
        XCTAssertEqual(r.confidence, .low)
        XCTAssertEqual(r.value!, r.components[0].score, accuracy: 0.1)
    }

    func testHRVScoreMapping() {
        XCTAssertEqual(ReadinessScorer.hrvScore(z: 0), 64.56, accuracy: 0.01)
        XCTAssertEqual(ReadinessScorer.hrvScore(z: 1), 85.81, accuracy: 0.01)
        XCTAssertEqual(ReadinessScorer.hrvScore(z: -1), 35.43, accuracy: 0.01)
    }

    func testSleepSubScores() {
        XCTAssertEqual(SleepScorer.durationScore(asleep: 480, goal: 480), 100)
        XCTAssertEqual(SleepScorer.durationScore(asleep: 360, goal: 480), 100 * pow(0.75, 1.5), accuracy: 1e-9)
        XCTAssertEqual(SleepScorer.efficiencyScore(0.95), 100)
        XCTAssertEqual(SleepScorer.efficiencyScore(0.70), 0)
        XCTAssertEqual(SleepScorer.bandScore(18, lo: 13, hi: 23), 100)
        XCTAssertEqual(SleepScorer.bandScore(8, lo: 13, hi: 23), 50)
        // Circular SD handles midnight wrap: 23:50 and 00:10 are 20 min apart.
        let a = Fixtures.iso("2024-03-10T23:50:00Z"), b = Fixtures.iso("2024-03-11T00:10:00Z")
        XCTAssertLessThan(SleepScorer.circularSDMinutes([a, b, a, b], calendar: cal), 15)
    }

    func testTRIMPAndStrainScale() {
        let p = HRProfile(maxHR: 190, restingHR: 60, sex: .male)
        let start = Fixtures.iso("2024-03-20T18:00:00Z")
        // 30 minutes at 60 % HRR (138 bpm), sampled every minute.
        let pts = (0...30).map { HRPoint(time: start.addingTimeInterval(Double($0) * 60), bpm: 138) }
        let expected = 30 * 0.6 * 0.64 * exp(1.92 * 0.6)
        XCTAssertEqual(StrainScorer.trimp(pts, profile: p), expected, accuracy: 1e-6)
        // Resting HR contributes nothing.
        let rest = (0...30).map { HRPoint(time: start.addingTimeInterval(Double($0) * 60), bpm: 65) }
        XCTAssertEqual(StrainScorer.trimp(rest, profile: p), 0)
        // Sparse readings are capped at 5 min per interval.
        let sparse = [HRPoint(time: start, bpm: 150), HRPoint(time: start.addingTimeInterval(3600), bpm: 150)]
        XCTAssertEqual(StrainScorer.trimp(sparse, profile: p), 5 * p.hrr(150) * 0.64 * exp(1.92 * p.hrr(150)), accuracy: 1e-6)
        XCTAssertEqual(StrainScorer.strain(fromTRIMP: 400), 21, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.strain(fromTRIMP: 0), 0)
        XCTAssertEqual(HRProfile.estimateMaxHR(age: 40, observedMax: 230), 180 + 15, "optical spikes capped")
        XCTAssertEqual(HRProfile.estimateMaxHR(age: nil, observedMax: nil), 190)
    }

    func testACWR() {
        var load: [DayKey: Double] = [:]
        for k in 0..<28 { load[day.addingDays(-k)] = k < 7 ? 120 : 100 }
        let r = StrainScorer.acwr(dailyLoad: load, day: day)!
        XCTAssertEqual(r.acute, 120, accuracy: 1e-9)
        XCTAssertEqual(r.chronic, 105, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.status(acwr: 1.33), .caution)
        XCTAssertEqual(StrainScorer.status(acwr: r.ratio), .optimal)
        XCTAssertEqual(StrainScorer.status(acwr: 1.6), .highRisk)
        XCTAssertEqual(StrainScorer.status(acwr: 0.5), .undertraining)
        XCTAssertNil(StrainScorer.acwr(dailyLoad: [day: 100], day: day), "needs history")
    }

    func testEnergyDrainsWithActivityAndRechargesAtRest() {
        let p = HRProfile(maxHR: 190, restingHR: 60)
        let t0 = Fixtures.iso("2024-03-20T08:00:00Z")
        func slots(_ hr: Double, steps: Double, n: Int) -> [EnergyModel.Slot] {
            (0..<n).map { EnergyModel.Slot(start: t0.addingTimeInterval(Double($0) * 900), avgHR: hr, steps: steps) }
        }
        let rest = EnergyModel.simulate(start: 60, slots: slots(62, steps: 0, n: 8), profile: p)
        XCTAssertGreaterThan(rest.end, 60, "calm rest recharges")
        let run = EnergyModel.simulate(start: 60, slots: slots(160, steps: 1500, n: 4), profile: p)
        XCTAssertLessThan(run.end, 40, "hard hour drains")
        let stress = EnergyModel.simulate(start: 60, slots: slots(90, steps: 0, n: 8), profile: p)
        XCTAssertLessThan(stress.end, 60 - 8 * EnergyModel.baselineDrainPerSlot, "elevated HR while still = stress drain")
        XCTAssertEqual(EnergyModel.startValue(sleepScore: 100, hrvSubScore: 100), 100)
        XCTAssertEqual(EnergyModel.startValue(sleepScore: 0, hrvSubScore: nil), 20)
    }

    func testGapFillingRules() {
        var m = baselineSeries(50, jitter: 1)
        m[day.addingDays(-1)] = 52
        // One missing day (today) → filled, estimated.
        let f = GapFiller.fillDaily(m, from: day, through: day)
        XCTAssertEqual(f[day]?.isEstimated, true)
        XCTAssertEqual(f[day]!.value, 0.5 * 52 + 0.5 * Baseline.compute(m, before: day, minDays: 7)!.mean, accuracy: 1e-9)
        XCTAssertNotNil(f[day]?.confidence)
        // A 4-day gap is NOT filled.
        var long = baselineSeries(50, jitter: 1)
        for k in 1...4 { long[day.addingDays(-k)] = nil }
        XCTAssertNil(GapFiller.fillDaily(long, from: day, through: day)[day])
        // Intraday: 1-hour HR gap filled, 5-hour gap not.
        let t0 = Fixtures.iso("2024-03-20T08:00:00Z")
        let short = GapFiller.fillSeries([(t0, 60), (t0.addingTimeInterval(3600), 80)])
        XCTAssertTrue(short.contains { $0.2 })
        XCTAssertEqual(short.filter { $0.2 }.count, 3)
        let longGap = GapFiller.fillSeries([(t0, 60), (t0.addingTimeInterval(5 * 3600), 80)])
        XCTAssertFalse(longGap.contains { $0.2 })
    }

    func testEstimatedHRVMarksReadinessEstimated() {
        let h = baselineSeries(50, jitter: 3)  // nothing for today
        var r = baselineSeries(56, jitter: 1); r[day] = 56
        let fill = GapFiller.fillDaily(h, from: day, through: day)[day]
        let res = ReadinessScorer.score(day: day, .init(hrv: h, hrvTodayFilled: fill, rhr: r, sleep: nil))
        XCTAssertTrue(res.isEstimated)
        XCTAssertLessThanOrEqual(res.confidence, .medium)
        XCTAssertTrue(res.components.first { $0.name == "HRV" }!.isEstimated)
    }
}
