import XCTest
@testable import PulseCore

private struct DedupFixture: Decodable {
    struct Cumulative: Decodable {
        let name: String
        let timeZone: String
        let priority: [String]
        let samples: [FixtureSample]
        let expectedTotal: Double
        let expectedDaily: [String: Double]
    }
    struct SleepExpected: Decodable {
        let nights: Int
        let day: String
        let asleepMinutes: Double
        let awakeMinutes: Double
        let inBedMinutes: Double
        let stageMinutes: [String: Double]
        let primarySource: String
        let hasStages: Bool
    }
    struct SleepCase: Decodable {
        let name: String
        let timeZone: String
        let priority: [String]
        let samples: [FixtureSample]?
        let samplesFrom: Int?
        let expected: SleepExpected
    }
    struct WorkoutExpected: Decodable {
        let id: String
        let mergedFrom: String?
        let energyKcal: String?
        let distanceM: String?
    }
    struct WorkoutCase: Decodable {
        let name: String
        let priority: [String]
        let samples: [FixtureSample]
        let expected: [WorkoutExpected]
    }
    struct DiscreteCase: Decodable {
        let name: String
        let priority: [String]
        let preferred: String?
        let counts: [String: Int]
        let expectedSource: String
    }
    let sources: [String: FixtureSource]
    let cumulative: [Cumulative]
    let sleep: [SleepCase]
    let workouts: [WorkoutCase]
    let discrete: [DiscreteCase]
}

final class DedupTests: XCTestCase {
    private func fixture() throws -> DedupFixture { try Fixtures.decode(DedupFixture.self, "dedup_cases.json") }

    func testCumulativeCases() throws {
        let f = try fixture()
        for c in f.cumulative {
            let samples = c.samples.map { $0.sample(f.sources) }
            let p = SourcePriority(ordered: c.priority)
            XCTAssertClose(CumulativeDeduper.total(samples, priority: p), c.expectedTotal, c.name)
            let cal = Calendar.pulse(TimeZone(identifier: c.timeZone)!)
            let daily = CumulativeDeduper.dailyTotals(samples, priority: p, calendar: cal)
            XCTAssertEqual(daily.count, c.expectedDaily.count, c.name)
            for (k, v) in c.expectedDaily {
                XCTAssertClose(daily[DayKey(string: k)!], v, "\(c.name) \(k)")
            }
        }
    }

    func testCumulativeSegmentsDoNotOverlap() throws {
        let f = try fixture()
        for c in f.cumulative {
            let segs = CumulativeDeduper.dedupe(c.samples.map { $0.sample(f.sources) }, priority: SourcePriority(ordered: c.priority))
            for (a, b) in zip(segs, segs.dropFirst()) { XCTAssertLessThanOrEqual(a.end, b.start, c.name) }
        }
    }

    func testSleepCases() throws {
        let f = try fixture()
        for c in f.sleep {
            let fs = c.samples ?? f.sleep[c.samplesFrom!].samples!
            let samples = fs.map { $0.sample(f.sources) }
            let cal = Calendar.pulse(TimeZone(identifier: c.timeZone)!)
            let nights = SleepMerger.nights(samples, priority: SourcePriority(ordered: c.priority), calendar: cal)
            XCTAssertEqual(nights.count, c.expected.nights, c.name)
            let n = try XCTUnwrap(nights.first)
            XCTAssertEqual(n.day.description, c.expected.day, c.name)
            XCTAssertClose(n.asleepMinutes, c.expected.asleepMinutes, c.name)
            XCTAssertClose(n.awakeMinutes, c.expected.awakeMinutes, c.name)
            XCTAssertClose(n.inBedMinutes, c.expected.inBedMinutes, c.name)
            XCTAssertEqual(n.primarySource.key, c.expected.primarySource, c.name)
            XCTAssertEqual(n.hasStages, c.expected.hasStages, c.name)
            let names: [String: SleepStage] = ["core": .core, "deep": .deep, "rem": .rem, "awake": .awake, "asleep": .asleepUnspecified]
            for (k, v) in c.expected.stageMinutes {
                XCTAssertClose(n.stageMinutes[names[k]!], v, "\(c.name) \(k)")
            }
            let expectedStageKeys = Set(c.expected.stageMinutes.keys.map { names[$0]! })
            XCTAssertEqual(Set(n.stageMinutes.filter { $0.value > 0 }.keys), expectedStageKeys, c.name)
        }
    }

    func testSleepSplitsSeparateNights() {
        let src = SourceRef(bundleId: "com.apple.health.1", name: "Watch")
        let cal = Calendar.pulse(TimeZone(identifier: "UTC")!)
        func s(_ id: String, _ a: String, _ b: String) -> Sample {
            Sample(id: id, type: .sleep, value: 3, unit: .stageCode, start: Fixtures.iso(a), end: Fixtures.iso(b), source: src)
        }
        let nights = SleepMerger.nights([
            s("a", "2024-03-10T23:00:00Z", "2024-03-11T07:00:00Z"),
            s("b", "2024-03-11T23:00:00Z", "2024-03-12T06:00:00Z"),
        ], priority: .default, calendar: cal)
        XCTAssertEqual(nights.map(\.day.description), ["2024-03-11", "2024-03-12"])
        XCTAssertEqual(nights.map(\.asleepMinutes), [480, 420])
    }

    func testWorkoutCases() throws {
        let f = try fixture()
        for c in f.workouts {
            let merged = WorkoutMerger.merge(c.samples.map { $0.sample(f.sources) }, priority: SourcePriority(ordered: c.priority))
            XCTAssertEqual(merged.map(\.id), c.expected.map(\.id), c.name)
            for (m, e) in zip(merged, c.expected) {
                XCTAssertEqual(m.metadata?[WorkoutInfo.mergedFromKey], e.mergedFrom, c.name)
                if let en = e.energyKcal { XCTAssertEqual(m.metadata?[WorkoutInfo.energyKey], en, c.name) }
                if let d = e.distanceM { XCTAssertEqual(m.metadata?[WorkoutInfo.distanceKey], d, c.name) }
            }
        }
    }

    func testDiscreteCases() throws {
        let f = try fixture()
        for c in f.discrete {
            var samples: [Sample] = []
            for (src, n) in c.counts {
                for i in 0..<n {
                    let fs = FixtureSample(id: "\(src)\(i)", type: "heartRate", value: 60, start: Date(timeIntervalSince1970: Double(i * 60)),
                                           end: Date(timeIntervalSince1970: Double(i * 60)), source: src, isManual: nil, isEstimated: nil, metadata: nil)
                    samples.append(fs.sample(f.sources))
                }
            }
            let chosen = DiscreteSourceSelector.select(samples, preferredSourceKey: c.preferred, priority: SourcePriority(ordered: c.priority))
            XCTAssertEqual(Set(chosen.map(\.source.key)), [c.expectedSource], c.name)
        }
    }

    func testVendorHeuristicOrdering() {
        let p = SourcePriority.default
        let watch = SourceRef(bundleId: "com.apple.health.9F1C", name: "Alex's Apple Watch")
        let phone = SourceRef(bundleId: "com.apple.health.81A2", name: "Alex's iPhone")
        let garmin = SourceRef(bundleId: "com.garmin.connect.mobile", name: "Connect")
        XCTAssertLessThan(p.rank(watch, device: DeviceRef(model: "Watch")), p.rank(garmin))
        XCTAssertLessThan(p.rank(garmin), p.rank(phone, device: DeviceRef(model: "iPhone")))
        XCTAssertEqual(p.preferring(phone.key).rank(phone), 0)
    }
}
