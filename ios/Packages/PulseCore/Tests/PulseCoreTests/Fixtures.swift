import Foundation
import XCTest
@testable import PulseCore

/// Loads shared JSON fixtures from /docs/fixtures (repo root), so iOS and web
/// tests assert against exactly the same expected values.
enum Fixtures {
    static var directory: URL {
        // .../ios/Packages/PulseCore/Tests/PulseCoreTests/Fixtures.swift → repo root
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("docs/fixtures")
    }

    static func json(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let data = try Data(contentsOf: directory.appendingPathComponent(name))
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(T.self, from: data)
    }

    static func iso(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }
}

/// Fixture sample format shared by dedup/score fixtures.
struct FixtureSource: Decodable {
    let sourceName: String
    let sourceBundleId: String
    let deviceModel: String?
    let deviceManufacturer: String?
}

struct FixtureSample: Decodable {
    let id: String
    let type: String
    let value: Double
    let start: Date
    let end: Date
    let source: String
    let isManual: Bool?
    let isEstimated: Bool?
    let metadata: [String: String]?

    func sample(_ sources: [String: FixtureSource]) -> Sample {
        let src = sources[source]!
        let dev: DeviceRef? = (src.deviceModel != nil || src.deviceManufacturer != nil)
            ? DeviceRef(name: nil, model: src.deviceModel, manufacturer: src.deviceManufacturer) : nil
        let metric = MetricID(type)
        return Sample(id: id, type: metric, value: value, unit: MetricRegistry.type(metric)?.unit ?? .count,
                      start: start, end: end, source: SourceRef(bundleId: src.sourceBundleId, name: src.sourceName),
                      device: dev, isManual: isManual ?? false, isEstimated: isEstimated ?? false, metadata: metadata)
    }
}

func XCTAssertClose(_ a: Double?, _ b: Double, accuracy: Double = 1e-4, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let a else { return XCTFail("nil value. \(msg)", file: file, line: line) }
    XCTAssertEqual(a, b, accuracy: accuracy, msg, file: file, line: line)
}
