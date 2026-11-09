import XCTest
@testable import PulseCore

final class ExportTests: XCTestCase {
    func testSharedExportFixtures() throws {
        let json = try Fixtures.json("export_cases.json")
        let ds = json["dailySummary"] as! [String: Any]
        let metrics = (ds["metrics"] as! [String]).compactMap { MetricRegistry.type(MetricID($0)) }
        var rows: [MetricID: [DailyAggregate]] = [:]
        for r in ds["rows"] as! [[String: Any]] {
            let id = MetricID(r["metric"] as! String)
            rows[id, default: []].append(DailyAggregate(metric: id, day: DayKey(string: r["day"] as! String)!,
                                                        sum: (r["sum"] as? NSNumber)?.doubleValue, average: (r["average"] as? NSNumber)?.doubleValue,
                                                        count: 1, isEstimated: r["isEstimated"] as? Bool ?? false))
        }
        let csv = CSVExporter.dailySummary(metrics: metrics, rows: rows, from: DayKey(string: ds["from"] as! String)!, to: DayKey(string: ds["to"] as! String)!)
        XCTAssertEqual(csv, ds["expected"] as? String)

        for e in json["escaping"] as! [[String: String]] { XCTAssertEqual(CSVExporter.escape(e["in"]!), e["out"]) }
        for n in json["numbers"] as! [[String: Any]] {
            XCTAssertEqual(CSVExporter.number((n["in"] as! NSNumber).doubleValue), n["out"] as? String)
        }
    }

    func testSamplesCSVHasEveryField() {
        let s = Sample(id: "a", type: .water, value: 250, unit: .milliliter, start: Date(timeIntervalSince1970: 0),
                       end: Date(timeIntervalSince1970: 0), source: SourceRef(bundleId: "b", name: "My, App"), isManual: true,
                       metadata: ["HKFoodType": "Tea"])
        let csv = CSVExporter.samples([s])
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0].split(separator: ",").count, 12)
        XCTAssertEqual(lines[1], "a,water,250,mL,1970-01-01T00:00:00Z,1970-01-01T00:00:00Z,\"My, App\",b,,true,false,HKFoodType=Tea")
    }

    func testScoresCSV() {
        let d = DayKey(year: 2024, month: 3, day: 10)
        let csv = CSVExporter.scores([ScoreResult(kind: .readiness, day: d, value: 77.44), ScoreResult(kind: .sleep, day: d, value: 90, isEstimated: true)],
                                     from: d, to: d.addingDays(1))
        XCTAssertEqual(csv, "date,readiness,sleep_score,strain,energy,estimated\r\n2024-03-10,77.4,90,,,yes\r\n2024-03-11,,,,,\r\n")
    }
}
