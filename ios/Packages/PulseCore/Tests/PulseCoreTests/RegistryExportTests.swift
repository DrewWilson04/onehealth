import XCTest
@testable import PulseCore

/// Keeps docs/fixtures/metrics_registry.json (imported directly by the web
/// app) identical to MetricRegistry. Run with RECORD_FIXTURES=1 to rewrite.
final class RegistryExportTests: XCTestCase {
    func registryJSON() throws -> Data {
        let rows: [[String: Any]] = MetricRegistry.all.map { m in
            var d: [String: Any] = ["id": m.id.rawValue, "displayName": m.displayName, "unit": m.unit.rawValue, "kind": m.kind.rawValue,
                                    "dailyStatistic": m.dailyStatistic.rawValue, "section": m.section.rawValue,
                                    "isHighVolume": m.isHighVolume, "isWritable": m.isWritable, "symbol": m.symbol]
            d["healthKitIdentifier"] = m.healthKitIdentifier ?? NSNull()
            d["higherIsBetter"] = m.higherIsBetter.map { $0 as Any } ?? NSNull()
            return d
        }
        return try JSONSerialization.data(withJSONObject: ["metrics": rows], options: [.prettyPrinted, .sortedKeys])
    }

    func testRegistryFixtureIsUpToDate() throws {
        let url = Fixtures.directory.appendingPathComponent("metrics_registry.json")
        let data = try registryJSON()
        if ProcessInfo.processInfo.environment["RECORD_FIXTURES"] == "1" {
            try data.write(to: url)
            return
        }
        let onDisk = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let now = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(NSDictionary(dictionary: onDisk), NSDictionary(dictionary: now),
                       "metrics_registry.json is stale — run RECORD_FIXTURES=1 swift test --filter RegistryExportTests")
    }
}
