import XCTest
@testable import PulseCore

final class AggregationTests: XCTestCase {
    private func json() throws -> [String: Any] { try Fixtures.json("aggregation_cases.json") }

    private func dailyRows(_ dict: [String: Any], metric: MetricType) -> [DailyAggregate] {
        dict.map { k, v in
            let value = (v as! NSNumber).doubleValue
            let day = DayKey(string: k)!
            switch metric.dailyStatistic {
            case .sum, .durationMinutes, .count:
                return DailyAggregate(metric: metric.id, day: day, sum: value, count: 1)
            default:
                return DailyAggregate(metric: metric.id, day: day, average: value, min: value, max: value, latest: value, count: 1)
            }
        }.sorted { $0.day < $1.day }
    }

    func testStepsRollupsComparisonAndBests() throws {
        let c = try XCTUnwrap(json()["steps"] as? [String: Any])
        let m = MetricRegistry.type(.steps)!
        let daily = dailyRows(c["daily"] as! [String: Any], metric: m)
        let weekly = Aggregator.rollup(daily, metric: m, to: .week)
        let expW = c["expectedWeekly"] as! [String: [String: Double]]
        XCTAssertEqual(weekly.count, expW.count)
        for w in weekly {
            let e = try XCTUnwrap(expW[w.day.description], "week \(w.day)")
            XCTAssertClose(w.sum, e["sum"]!)
            XCTAssertClose(w.average, e["average"]!)
            XCTAssertEqual(w.count, Int(e["count"]!))
        }
        let monthly = Aggregator.rollup(daily, metric: m, to: .month)
        let expM = c["expectedMonthly"] as! [String: [String: Double]]
        XCTAssertClose(monthly.first?.sum, expM["2024-03-01"]!["sum"]!)
        XCTAssertEqual(monthly.first?.day.description, "2024-03-01")

        let pts = Trends.points(daily, metric: m)
        let rolling = Trends.rollingAverage(pts, window: 3, minCount: 3)
        let expR = c["expectedRolling3"] as! [String: Double]
        let byDay = Dictionary(uniqueKeysWithValues: rolling.map { ($0.day.description, $0.value) })
        for (k, v) in expR { XCTAssertClose(byDay[k], v, "rolling \(k)") }
        XCTAssertNil(byDay["2024-03-04"])
        XCTAssertNil(byDay["2024-03-05"])

        let today = DayKey(string: c["today"] as! String)!
        let cmp = Trends.compare(daily, metric: m, period: .week, today: today)
        let expC = c["expectedWeekComparison"] as! [String: Double]
        XCTAssertClose(cmp.current, expC["current"]!)
        XCTAssertClose(cmp.previous, expC["previous"]!)
        XCTAssertClose(cmp.percentChange, expC["percentChange"]!)
        XCTAssertEqual(cmp.currentDays, Int(expC["currentDays"]!))
        XCTAssertEqual(cmp.previousDays, Int(expC["previousDays"]!))
        XCTAssertEqual(cmp.direction(higherIsBetter: true), 1)

        let bests = Trends.personalBests(daily: daily, weekly: weekly, monthly: monthly, metric: m)
        let bd = c["expectedBestDay"] as! [String: Any]
        XCTAssertEqual(bests.first { $0.period == .day }?.day.description, bd["day"] as? String)
        XCTAssertClose(bests.first { $0.period == .day }?.value, (bd["value"] as! NSNumber).doubleValue)
        let bw = c["expectedBestWeek"] as! [String: Any]
        XCTAssertEqual(bests.first { $0.period == .week }?.day.description, bw["day"] as? String)
        XCTAssertClose(bests.first { $0.period == .week }?.value, (bw["value"] as! NSNumber).doubleValue)
    }

    func testDiscreteRollupAndLowerIsBetterBest() throws {
        let c = try XCTUnwrap(json()["rhr"] as? [String: Any])
        let m = MetricRegistry.type(.restingHeartRate)!
        let daily = dailyRows(c["daily"] as! [String: Any], metric: m)
        let weekly = Aggregator.rollup(daily, metric: m, to: .week)
        let expW = c["expectedWeekly"] as! [String: [String: Double]]
        for w in weekly {
            let e = try XCTUnwrap(expW[w.day.description])
            XCTAssertClose(w.average, e["average"]!)
            XCTAssertEqual(w.count, Int(e["count"]!))
        }
        let bests = Trends.personalBests(daily: daily, weekly: weekly, monthly: [], metric: m)
        let bd = c["expectedBestDay"] as! [String: Any]
        XCTAssertEqual(bests.count, 1, "discrete metrics only have a best day")
        XCTAssertEqual(bests[0].day.description, bd["day"] as? String)
        XCTAssertClose(bests[0].value, (bd["value"] as! NSNumber).doubleValue)
    }

    func testRollingAverageSkipsGaps() throws {
        let c = try XCTUnwrap(json()["rollingGaps"] as? [String: Any])
        let pts = (c["points"] as! [String: Double]).map { TrendPoint(day: DayKey(string: $0.key)!, value: $0.value) }
        let r = Trends.rollingAverage(pts, window: c["window"] as! Int, minCount: c["minCount"] as! Int)
        let exp = c["expected"] as! [String: Double]
        XCTAssertEqual(r.count, exp.count)
        for p in r { XCTAssertClose(exp[p.day.description], p.value) }
    }

    func testDiscreteDailyFromSamples() throws {
        let c = try XCTUnwrap(json()["discreteDaily"] as? [String: Any])
        let dedup = try Fixtures.json("dedup_cases.json")
        let srcData = try JSONSerialization.data(withJSONObject: dedup["sources"]!)
        let sources = try JSONDecoder().decode([String: FixtureSource].self, from: srcData)
        let sData = try JSONSerialization.data(withJSONObject: c["samples"]!)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let samples = try d.decode([FixtureSample].self, from: sData).map { $0.sample(sources) }
        let opts = Aggregator.Options(calendar: .pulse(TimeZone(identifier: "UTC")!))
        let rows = Aggregator.daily(MetricRegistry.type(.heartRate)!, samples: samples, options: opts)
        let exp = (c["expected"] as! [String: [String: Any]])["2024-03-10"]!
        XCTAssertEqual(rows.count, 1)
        XCTAssertClose(rows[0].average, (exp["average"] as! NSNumber).doubleValue)
        XCTAssertClose(rows[0].min, (exp["min"] as! NSNumber).doubleValue)
        XCTAssertClose(rows[0].max, (exp["max"] as! NSNumber).doubleValue)
        XCTAssertClose(rows[0].latest, (exp["latest"] as! NSNumber).doubleValue)
        XCTAssertEqual(rows[0].count, exp["count"] as? Int)
        XCTAssertEqual(rows[0].primarySource.map { SourceRef(attribution: $0).key }, exp["primarySource"] as? String)
        XCTAssertEqual(rows[0].primarySource.map { SourceRef(attribution: $0).name }, "Alex's Apple Watch")
    }

    func testSleepAndWorkoutDailyRows() throws {
        let f = try Fixtures.json("dedup_cases.json")
        let srcData = try JSONSerialization.data(withJSONObject: f["sources"]!)
        let sources = try JSONDecoder().decode([String: FixtureSource].self, from: srcData)
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let sleep = (f["sleep"] as! [[String: Any]])[0]["samples"]!
        let sleepSamples = try d.decode([FixtureSample].self, from: JSONSerialization.data(withJSONObject: sleep)).map { $0.sample(sources) }
        let opts = Aggregator.Options(calendar: .pulse(TimeZone(identifier: "UTC")!))
        let s = Aggregator.daily(MetricRegistry.type(.sleep)!, samples: sleepSamples, options: opts)
        XCTAssertEqual(s.count, 1)
        XCTAssertClose(s[0].sum, 400)
        XCTAssertClose(s[0].max, 495)

        let w = (f["workouts"] as! [[String: Any]])[0]["samples"]!
        let wSamples = try d.decode([FixtureSample].self, from: JSONSerialization.data(withJSONObject: w)).map { $0.sample(sources) }
        let wr = Aggregator.daily(MetricRegistry.type(.workout)!, samples: wSamples, options: opts)
        XCTAssertEqual(wr.count, 1)
        XCTAssertEqual(wr[0].count, 2, "duplicates merged")
        XCTAssertClose(wr[0].sum, 75)
    }

    func testDayKeyArithmetic() {
        let d = DayKey(string: "2024-02-28")!
        XCTAssertEqual(d.addingDays(1).description, "2024-02-29")
        XCTAssertEqual(d.addingDays(2).description, "2024-03-01")
        XCTAssertEqual(DayKey(string: "2024-03-13")!.weekStart.description, "2024-03-11")
        XCTAssertEqual(DayKey(string: "2024-03-10")!.isoWeekday, 7)
        XCTAssertEqual(DayKey.daysBetween(DayKey(string: "2023-12-31")!, DayKey(string: "2024-01-01")!), 1)
        let ny = Calendar.pulse(TimeZone(identifier: "America/New_York")!)
        // DST transition day still maps to one DayKey.
        XCTAssertEqual(DayKey(Fixtures.iso("2024-03-10T12:00:00Z"), calendar: ny).description, "2024-03-10")
        XCTAssertEqual(DayKey(string: "2024-03-10")!.interval(in: ny).duration, 23 * 3600)
    }
}
