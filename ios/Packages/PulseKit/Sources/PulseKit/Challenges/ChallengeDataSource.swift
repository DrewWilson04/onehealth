import Foundation
import HealthKit
import PulseCore

/// Builds competition-eligible daily `ActivityInputs` from HealthKit:
/// manual entries (HKWasUserEntered) and estimated values are excluded.
public actor ChallengeDataSource {
    let provider: HealthKitProvider
    let store: LocalStore
    let calendar: Calendar
    private var cache: [DayKey: ActivityInputs] = [:]

    public init(provider: HealthKitProvider, store: LocalStore, calendar: Calendar = .pulse()) {
        self.provider = provider
        self.store = store
        self.calendar = calendar
    }

    public func invalidate(_ days: Set<DayKey>) { for d in days { cache[d] = nil } }

    static var notManual: NSPredicate {
        NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyWasUserEntered, operatorType: .equalTo, value: true))
    }

    func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, interval: DateInterval) async -> Double? {
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: []), Self.notManual])
        guard let coll = try? await provider.store.statisticsCollection(of: HKQuantityType(id), predicate: pred, options: [.cumulativeSum],
                                                                         anchor: interval.start, interval: DateComponents(day: 1)) else { return nil }
        var total: Double?
        coll.enumerateStatistics(from: interval.start, to: interval.end) { s, _ in
            if let v = s.sumQuantity()?.doubleValue(for: unit) { total = (total ?? 0) + v }
        }
        return total
    }

    public func inputs(for day: DayKey) async -> ActivityInputs {
        if let c = cache[day], day < DayKey(Date(), calendar: calendar) { return c }
        let iv = day.interval(in: calendar)
        let steps = await sum(.stepCount, unit: .count(), interval: iv)
        let exercise = await sum(.appleExerciseTime, unit: .minute(), interval: iv)

        // Workouts: non-manual, merged across devices.
        let workouts = WorkoutMerger.merge(((try? await store.samples(.workout, from: iv.start, to: iv.end)) ?? [])
            .filter { $0.isCompetitionEligible && DayKey($0.start, calendar: calendar) == day }, priority: .default)

        // HR zone minutes during the whole day (measured HR only).
        var zones: [Int: Double] = [:]
        let rhrRows = (try? await store.aggregates(.restingHeartRate, period: .day, from: day.addingDays(-30), to: day)) ?? []
        let rest = rhrRows.compactMap(\.average)
        if !rest.isEmpty, let hr = try? await provider.heartRateSeries(iv, calendar: calendar), hr.count > 10 {
            let profile = HRProfile(maxHR: HRProfile.estimateMaxHR(age: provider.age(), observedMax: nil),
                                    restingHR: rest.reduce(0, +) / Double(rest.count), sex: provider.biologicalSex())
            zones = StrainScorer.zoneMinutes(hr, profile: profile)
        }

        let sleepSamples = ((try? await store.samples(.sleep, from: iv.start.addingTimeInterval(-12 * 3600), to: iv.end)) ?? [])
            .filter(\.isCompetitionEligible)
        let night = SleepMerger.nights(sleepSamples, priority: .default, calendar: calendar).first { $0.day == day }

        let i = ActivityInputs(steps: steps, exerciseMinutes: exercise, zoneMinutes: zones,
                               workoutMinutes: workouts.isEmpty ? nil : workouts.reduce(0) { $0 + $1.value },
                               sleepMinutes: night?.asleepMinutes)
        cache[day] = i
        return i
    }

    public func dailyValues(_ challenge: Challenge, today: DayKey) async -> [DayKey: Double] {
        let end = min(today, challenge.end)
        guard challenge.start <= end else { return [:] }
        var out: [DayKey: Double] = [:]
        for d in DayKey.range(challenge.start, through: end) {
            let i = await inputs(for: d)
            guard AntiCheat.check(i).isEmpty else { continue }
            out[d] = challenge.metric.dailyValue(i)
        }
        return out
    }
}
