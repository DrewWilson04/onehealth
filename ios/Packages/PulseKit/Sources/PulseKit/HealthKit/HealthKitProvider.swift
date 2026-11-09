import Foundation
import HealthKit
import PulseCore

/// Apple Health implementation of PulseCore's `DataProvider`.
public final class HealthKitProvider: DataProvider, @unchecked Sendable {
    public let id = "apple-health"
    public let displayName = "Apple Health"
    public let store: HKHealthStore
    let normalizer: HealthKitNormalizer

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
        self.normalizer = HealthKitNormalizer()
    }

    public func isAvailable() -> Bool { HKHealthStore.isHealthDataAvailable() }

    public func supportedMetrics() -> [MetricID] {
        MetricRegistry.all.filter { HKMapping.objectType(for: $0) != nil }.map(\.id)
    }

    // MARK: Authorization

    public func requestAuthorization(read: [MetricID], write: [MetricID]) async throws {
        let readTypes = HKMapping.readTypes(for: read.compactMap(MetricRegistry.type))
        let writeTypes = HKMapping.writeTypes(for: write.compactMap(MetricRegistry.type).filter(\.isWritable))
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    /// Whether the system would show the permission sheet for the full set.
    public func needsAuthorizationPrompt() async -> Bool {
        let status = try? await store.statusForAuthorizationRequest(toShare: HKMapping.writeTypes(), read: HKMapping.readTypes())
        return status == .shouldRequest || status == nil
    }

    /// HealthKit hides read denial (a denied type simply returns no data), so
    /// `hasData` is the only honest signal; write status is exact.
    public func accessSummary() async -> AccessSummary {
        var out: [MetricAccess] = []
        for m in MetricRegistry.all {
            guard let type = HKMapping.sampleType(for: m) else {
                out.append(MetricAccess(metric: m.id, read: .unavailable, write: .unavailable, hasData: false))
                continue
            }
            let write: AccessState
            if m.isWritable {
                switch store.authorizationStatus(for: type) {
                case .sharingAuthorized: write = .granted
                case .sharingDenied: write = .denied
                case .notDetermined: write = .notRequested
                @unknown default: write = .unknown
                }
            } else {
                write = .unavailable
            }
            let one = (try? await store.samples(of: type, predicate: nil, limit: 1)) ?? []
            out.append(MetricAccess(metric: m.id, read: one.isEmpty ? .unknown : .granted, write: write, hasData: !one.isEmpty))
        }
        return AccessSummary(metrics: out)
    }

    // MARK: Reads

    public func samples(of metric: MetricID, in interval: DateInterval) async throws -> [Sample] {
        guard let m = MetricRegistry.type(metric), let type = HKMapping.sampleType(for: m) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let hk = try await store.samples(of: type, predicate: pred, ascending: true)
        return hk.compactMap { normalizer.normalize($0, as: m) }
    }

    public func hkWorkout(id: String) async throws -> HKWorkout? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let pred = HKQuery.predicateForObject(with: uuid)
        return try await store.samples(of: .workoutType(), predicate: pred, limit: 1).first as? HKWorkout
    }

    /// Daily (or hourly) aggregates computed by HealthKit statistics. For
    /// cumulative types, `.merged` uses Apple Health's source priority; a
    /// preferred source uses `.separateBySource` and falls back to merged on
    /// days the preferred source has no data. Discrete types always use one
    /// source per day (see `DiscreteSourceSelector` for the rationale).
    public func dailyAggregates(of metric: MetricID, in interval: DateInterval, policy: SourcePolicy,
                                calendar: Calendar) async throws -> [DailyAggregate] {
        try await aggregates(of: metric, in: interval, policy: policy, calendar: calendar, hourly: false)
    }

    public func aggregates(of metric: MetricID, in interval: DateInterval, policy: SourcePolicy,
                           calendar: Calendar, hourly: Bool) async throws -> [DailyAggregate] {
        guard let m = MetricRegistry.type(metric), let qt = HKMapping.quantityType(for: m),
              let (unit, _) = HKMapping.hkUnit(for: m.unit) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let anchor = calendar.startOfDay(for: interval.start)
        let comps = hourly ? DateComponents(hour: 1) : DateComponents(day: 1)
        let scale = m.unit == .percent ? 100.0 : 1.0
        let period: DailyAggregate.Period = hourly ? .hour : .day

        if m.kind == .cumulative {
            // `.separateBySource` keeps the merged `sumQuantity()` (Apple Health
            // priority) and also lets us attribute the day ("via Garmin").
            let opts: HKStatisticsOptions = [.cumulativeSum, .separateBySource]
            let coll = try await store.statisticsCollection(of: qt, predicate: pred, options: opts, anchor: anchor, interval: comps)
            var out: [DailyAggregate] = []
            coll.enumerateStatistics(from: interval.start, to: interval.end) { stats, _ in
                var total = stats.sumQuantity()?.doubleValue(for: unit)
                var primary = stats.sources?.max(by: { a, b in
                    (stats.sumQuantity(for: a)?.doubleValue(for: unit) ?? 0) < (stats.sumQuantity(for: b)?.doubleValue(for: unit) ?? 0)
                }).map { SourceRef(bundleId: $0.bundleIdentifier, name: $0.name).attribution }
                if case .preferred(let key) = policy,
                   let src = stats.sources?.first(where: { $0.bundleIdentifier == key || $0.name == key }),
                   let v = stats.sumQuantity(for: src)?.doubleValue(for: unit) {
                    total = v
                    primary = SourceRef(bundleId: src.bundleIdentifier, name: src.name).attribution
                }
                guard let total else { return }
                let day = DayKey(stats.startDate, calendar: calendar)
                let hour = hourly ? calendar.component(.hour, from: stats.startDate) : nil
                out.append(DailyAggregate(metric: metric, period: period, day: day, hour: hour, sum: total * scale,
                                          count: 1, primarySource: primary, sourcePolicy: policy.key))
            }
            return out
        } else {
            let opts: HKStatisticsOptions = [.discreteAverage, .discreteMin, .discreteMax, .mostRecent, .separateBySource]
            let coll = try await store.statisticsCollection(of: qt, predicate: pred, options: opts, anchor: anchor, interval: comps)
            var out: [DailyAggregate] = []
            let preferredKey: String? = { if case .preferred(let k) = policy { return k }; return nil }()
            coll.enumerateStatistics(from: interval.start, to: interval.end) { stats, _ in
                guard let sources = stats.sources, !sources.isEmpty else { return }
                // One source per bucket: preferred if present, else the Apple
                // Watch/wearable-first heuristic from PulseCore.
                let pick: HKSource = {
                    if let k = preferredKey, let s = sources.first(where: { $0.bundleIdentifier == k || $0.name == k }) { return s }
                    let pr = SourcePriority.default
                    return sources.min { a, b in
                        pr.isHigher(SourceRef(bundleId: a.bundleIdentifier, name: a.name), nil,
                                    than: SourceRef(bundleId: b.bundleIdentifier, name: b.name), nil)
                    }!
                }()
                guard let avg = stats.averageQuantity(for: pick)?.doubleValue(for: unit) else { return }
                let day = DayKey(stats.startDate, calendar: calendar)
                let hour = hourly ? calendar.component(.hour, from: stats.startDate) : nil
                out.append(DailyAggregate(
                    metric: metric, period: period, day: day, hour: hour, average: avg * scale,
                    min: stats.minimumQuantity(for: pick).map { $0.doubleValue(for: unit) * scale },
                    max: stats.maximumQuantity(for: pick).map { $0.doubleValue(for: unit) * scale },
                    latest: stats.mostRecentQuantity(for: pick).map { $0.doubleValue(for: unit) * scale },
                    count: 1, primarySource: SourceRef(bundleId: pick.bundleIdentifier, name: pick.name).attribution, sourcePolicy: policy.key))
            }
            return out
        }
    }

    public func sources(for metric: MetricID) async throws -> [SourceRef] {
        guard let m = MetricRegistry.type(metric), let type = HKMapping.sampleType(for: m) else { return [] }
        return try await store.sources(for: type)
            .map { SourceRef(bundleId: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name < $1.name }
    }

    /// Anchored incremental changes (used by observers and backfill).
    public func changes(of metric: MetricType, since anchor: HKQueryAnchor?, interval: DateInterval? = nil,
                        limit: Int = HKObjectQueryNoLimit) async throws -> (added: [Sample], deleted: [String], anchor: HKQueryAnchor?) {
        guard let type = HKMapping.sampleType(for: metric) else { return ([], [], anchor) }
        let pred = interval.map { HKQuery.predicateForSamples(withStart: $0.start, end: $0.end, options: []) }
        let r = try await store.anchoredChanges(of: type, predicate: pred, anchor: anchor, limit: limit)
        return (r.added.compactMap { normalizer.normalize($0, as: metric) }, r.deleted.map { $0.uuid.uuidString }, r.anchor)
    }

    public func earliestDate() -> Date {
        store.earliestPermittedSampleDate()
    }

    public func dateOfBirth() -> DateComponents? {
        try? store.dateOfBirthComponents()
    }

    /// Activity ring goals/progress for the last `days` days.
    public func activityRings(days: Int, calendar: Calendar) async throws -> [DayKey: ActivityRings] {
        var cal = calendar
        cal.timeZone = calendar.timeZone
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: end)!
        var fromC = cal.dateComponents([.year, .month, .day, .era], from: start); fromC.calendar = cal
        var toC = cal.dateComponents([.year, .month, .day, .era], from: end); toC.calendar = cal
        let summaries = try await store.activitySummaries(from: fromC, to: toC)
        var out: [DayKey: ActivityRings] = [:]
        for s in summaries {
            let dc = s.dateComponents(for: cal)
            guard let y = dc.year, let mo = dc.month, let d = dc.day else { continue }
            out[DayKey(year: y, month: mo, day: d)] = ActivityRings(
                move: s.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                moveGoal: s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                exercise: s.appleExerciseTime.doubleValue(for: .minute()),
                exerciseGoal: s.exerciseTimeGoal?.doubleValue(for: .minute()) ?? s.appleExerciseTimeGoal.doubleValue(for: .minute()),
                stand: s.appleStandHours.doubleValue(for: .count()),
                standGoal: s.standHoursGoal?.doubleValue(for: .count()) ?? s.appleStandHoursGoal.doubleValue(for: .count()))
        }
        return out
    }
}

// MARK: - Inputs for derived scores

extension HealthKitProvider {
    /// Minute-resolution heart rate for an interval (one source per minute is
    /// not needed here: HealthKit's discrete average across simultaneous
    /// sources is fine for zone time).
    public func heartRateSeries(_ interval: DateInterval, calendar: Calendar, minutes: Int = 1) async throws -> [HRPoint] {
        let type = HKQuantityType(.heartRate)
        let pred = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let coll = try await store.statisticsCollection(of: type, predicate: pred, options: [.discreteAverage],
                                                        anchor: calendar.startOfDay(for: interval.start),
                                                        interval: DateComponents(minute: minutes))
        let unit = HKUnit.count().unitDivided(by: .minute())
        var out: [HRPoint] = []
        coll.enumerateStatistics(from: interval.start, to: interval.end) { s, _ in
            if let v = s.averageQuantity()?.doubleValue(for: unit) { out.append(HRPoint(time: s.startDate, bpm: v)) }
        }
        return out
    }

    /// Step totals in fixed buckets (default 15 min).
    public func stepBuckets(_ interval: DateInterval, calendar: Calendar, minutes: Int = 15) async throws -> [(Date, Double)] {
        let pred = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let coll = try await store.statisticsCollection(of: HKQuantityType(.stepCount), predicate: pred, options: [.cumulativeSum],
                                                        anchor: calendar.startOfDay(for: interval.start),
                                                        interval: DateComponents(minute: minutes))
        var out: [(Date, Double)] = []
        coll.enumerateStatistics(from: interval.start, to: interval.end) { s, _ in
            if let v = s.sumQuantity()?.doubleValue(for: .count()) { out.append((s.startDate, v)) }
        }
        return out
    }

    public func biologicalSex() -> BiologicalSex {
        switch (try? store.biologicalSex())?.biologicalSex {
        case .female: return .female
        case .male: return .male
        case .other: return .other
        default: return .unknown
        }
    }

    public func age(on date: Date = Date()) -> Double? {
        guard let dob = dateOfBirth(), let d = Calendar(identifier: .gregorian).date(from: dob) else { return nil }
        return date.timeIntervalSince(d) / (365.25 * 86_400)
    }
}
