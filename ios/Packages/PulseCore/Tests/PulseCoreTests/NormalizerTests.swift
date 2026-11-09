import XCTest
@testable import PulseCore

final class NormalizerTests: XCTestCase {
    func raw(from dict: [String: Any]) -> RawSample {
        let valueString = dict["value"] as? String
        let numeric = valueString.flatMap(Double.init)
        return RawSample(
            typeIdentifier: dict["type"] as! String,
            value: numeric,
            stringValue: numeric == nil ? valueString : nil,
            unit: dict["unit"] as? String,
            start: HealthDate.parse(dict["startDate"] as! String)!,
            end: HealthDate.parse(dict["endDate"] as! String)!,
            sourceName: dict["sourceName"] as! String,
            sourceBundleId: dict["sourceBundleId"] as? String ?? "",
            device: (dict["device"] as? String).flatMap(DeviceRef.parseExportDescription),
            metadata: dict["metadata"] as? [String: String] ?? [:],
            uuid: nil
        )
    }

    func testSharedFixtureCases() throws {
        let json = try Fixtures.json("normalizer_cases.json")
        let cases = try XCTUnwrap(json["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 10)
        let normalizer = Normalizer(ownBundleIdPrefix: "")
        for c in cases {
            let name = c["name"] as! String
            let result = normalizer.normalize(raw(from: c["raw"] as! [String: Any]))
            if let expected = c["expected"] as? [String: Any] {
                let s = try XCTUnwrap(result.sample, name)
                XCTAssertEqual(s.type.rawValue, expected["type"] as? String, name)
                XCTAssertClose(s.value, (expected["value"] as! NSNumber).doubleValue, accuracy: 1e-3, name)
                XCTAssertEqual(s.unit.rawValue, expected["unit"] as? String, name)
                XCTAssertEqual(s.start, Fixtures.iso(expected["start"] as! String), name)
                XCTAssertEqual(s.end, Fixtures.iso(expected["end"] as! String), name)
                XCTAssertEqual(s.isManual, expected["isManual"] as? Bool, name)
                XCTAssertEqual(s.vendor.rawValue, expected["vendor"] as? String, name)
                if let model = expected["deviceModel"] as? String { XCTAssertEqual(s.device?.model, model, name) }
                if let hw = expected["deviceHardware"] as? String { XCTAssertEqual(s.device?.hardwareVersion, hw, name) }
                XCTAssertFalse(s.isEstimated)
            } else {
                XCTAssertNil(result.sample, name)
                XCTAssertEqual(result.issue?.rawValue, c["expectedIssue"] as? String, name)
            }
        }
    }

    func testStableIdMatchesSharedFixture() throws {
        let json = try Fixtures.json("normalizer_cases.json")
        let st = try XCTUnwrap(json["stableId"] as? [String: Any])
        let r = raw(from: st["raw"] as! [String: Any])
        let id = Normalizer.stableId(r)
        let expected = st["expected"] as! String
        if expected == "FILLED_BY_TEST" {
            print("STABLE_ID=\(id)")
        } else {
            XCTAssertEqual(id, expected)
        }
        XCTAssertEqual(Normalizer.stableId(r), id, "deterministic")
    }

    func testHealthDateParsing() {
        XCTAssertEqual(HealthDate.parse("2024-03-10 08:00:00 -0500"), Fixtures.iso("2024-03-10T13:00:00Z"))
        XCTAssertEqual(HealthDate.parse("2024-03-10 08:00:00 +0530"), Fixtures.iso("2024-03-10T02:30:00Z"))
        XCTAssertEqual(HealthDate.parse("1999-12-31 23:59:59 +0000"), Fixtures.iso("1999-12-31T23:59:59Z"))
        XCTAssertNil(HealthDate.parse("garbage"))
    }

    func testDeviceParsing() {
        let d = DeviceRef.parseExportDescription("<<HKDevice: 0x283b0d2c0>, name:Apple Watch, manufacturer:Apple Inc., model:Watch, hardware:Watch6,1, software:9.1>")
        XCTAssertEqual(d?.name, "Apple Watch")
        XCTAssertEqual(d?.manufacturer, "Apple Inc.")
        XCTAssertEqual(d?.model, "Watch")
        XCTAssertEqual(d?.hardwareVersion, "Watch6,1")
    }

    func testOwnAppIsManual() {
        let n = Normalizer(ownBundleIdPrefix: "com.example.pulseboard")
        let r = RawSample(typeIdentifier: "HKQuantityTypeIdentifierDietaryWater", value: 250, unit: "mL",
                          start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 0),
                          sourceName: "PulseBoard", sourceBundleId: "com.example.pulseboard")
        XCTAssertEqual(n.normalize(r).sample?.isManual, true)
    }

    func testWorkoutNormalization() {
        let n = Normalizer(ownBundleIdPrefix: "")
        let w = n.normalizeWorkout(activityType: "HKWorkoutActivityTypeRunning", start: Date(timeIntervalSince1970: 0),
                                   end: Date(timeIntervalSince1970: 1800), durationMinutes: 30, energyKcal: 300,
                                   distanceMeters: 5000, hasRoute: true, sourceName: "Watch", sourceBundleId: "com.apple.health.1",
                                   device: nil, metadata: [:], uuid: "U1")
        let info = WorkoutInfo(w)!
        XCTAssertEqual(info.activityType, "running")
        XCTAssertEqual(info.energyKcal, 300)
        XCTAssertEqual(info.distanceMeters, 5000)
        XCTAssertTrue(info.hasRoute)
        XCTAssertEqual(w.id, "U1")
    }

    func testRegistryIsConsistent() {
        let ids = MetricRegistry.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate metric ids")
        let hk = MetricRegistry.all.compactMap(\.healthKitIdentifier)
        XCTAssertEqual(Set(hk).count, hk.count, "duplicate HK identifiers")
        for section in DashboardSection.allCases { XCTAssertFalse(MetricRegistry.metrics(in: section).isEmpty) }
    }
}
