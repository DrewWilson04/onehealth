import Foundation
import HealthKit
import PulseCore

public enum HealthWriteError: LocalizedError {
    case notAuthorized(String)
    case unsupported(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notAuthorized(let t): return "\(PulseKitConfig.appName) isn't allowed to save \(t) to Apple Health. Turn it on in Settings → Health → Data Access & Devices."
        case .unsupported(let t): return "\(t) can't be saved to Apple Health."
        case .notFound: return "That entry no longer exists in Apple Health."
        }
    }
}

/// Writes manual entries to HealthKit (which syncs them across the user's
/// iPhone, iPad and Apple Watch). Every object carries
/// HKMetadataKeyWasUserEntered so it is tagged `isManual` on read-back and
/// excluded from challenge scoring.
public final class HealthWriter: @unchecked Sendable {
    let store: HKHealthStore
    public init(store: HKHealthStore) { self.store = store }

    public static let mealKey = "PulseBoardMeal"
    private func baseMetadata(_ extra: [String: Any] = [:]) -> [String: Any] {
        var m: [String: Any] = [HKMetadataKeyWasUserEntered: true]
        for (k, v) in extra { m[k] = v }
        return m
    }

    private func ensureAuthorized(_ type: HKObjectType, _ name: String) throws {
        if store.authorizationStatus(for: type) != .sharingAuthorized { throw HealthWriteError.notAuthorized(name) }
    }

    private func quantitySample(_ id: MetricID, _ value: Double, _ start: Date, _ end: Date? = nil,
                                metadata: [String: Any] = [:]) throws -> HKQuantitySample {
        guard let m = MetricRegistry.type(id), let type = HKMapping.quantityType(for: m),
              let q = HKMapping.quantity(value, for: m) else { throw HealthWriteError.unsupported(id.rawValue) }
        try ensureAuthorized(type, m.displayName)
        return HKQuantitySample(type: type, quantity: q, start: start, end: end ?? start, metadata: baseMetadata(metadata))
    }

    // MARK: Simple quantities (water, weight, body fat, glucose, temperature...)

    @discardableResult
    public func log(_ metric: MetricID, value: Double, at date: Date) async throws -> String {
        let s = try quantitySample(metric, value, date)
        try await store.save(s)
        return s.uuid.uuidString
    }

    // MARK: Food

    /// Saves a food as an HKCorrelation(.food) of nutrient samples. Zero
    /// macros are omitted. Returns the correlation UUID.
    @discardableResult
    public func logFood(_ f: FoodEntry) async throws -> String {
        let meta: [String: Any] = [HKMetadataKeyFoodType: f.name, Self.mealKey: f.meal.rawValue]
        var objects = Set<HKSample>()
        objects.insert(try quantitySample(.dietaryEnergy, f.kcal, f.date, metadata: meta))
        let parts: [(MetricID, Double?)] = [(.protein, f.protein), (.carbohydrates, f.carbs), (.fat, f.fat),
                                            (.fiber, f.fiber), (.sugar, f.sugar), (.sodium, f.sodium)]
        for (id, v) in parts {
            if let v, v > 0 { objects.insert(try quantitySample(id, v, f.date, metadata: meta)) }
        }
        let corr = HKCorrelation(type: HKCorrelationType(.food), start: f.date, end: f.date, objects: objects,
                                 metadata: baseMetadata(meta))
        try await store.save(corr)
        return corr.uuid.uuidString
    }

    // MARK: Blood pressure

    @discardableResult
    public func logBloodPressure(systolic: Double, diastolic: Double, at date: Date) async throws -> String {
        let sys = try quantitySample(.bloodPressureSystolic, systolic, date)
        let dia = try quantitySample(.bloodPressureDiastolic, diastolic, date)
        let corr = HKCorrelation(type: HKCorrelationType(.bloodPressure), start: date, end: date,
                                 objects: [sys, dia], metadata: baseMetadata())
        try await store.save(corr)
        return corr.uuid.uuidString
    }

    // MARK: Workouts (with strength sets)

    /// Writes a workout via HKWorkoutBuilder. Strength sets are stored as JSON
    /// in the workout's metadata under `PulseBoardSets` because HealthKit has
    /// no sets/reps/weight types; the metadata syncs with the workout.
    @discardableResult
    public func logWorkout(activityType: String, start: Date, durationMinutes: Double, energyKcal: Double?,
                           distanceMeters: Double?, sets: [ExerciseSet]) async throws -> String {
        try ensureAuthorized(HKObjectType.workoutType(), "workouts")
        let end = start.addingTimeInterval(durationMinutes * 60)
        let config = HKWorkoutConfiguration()
        config.activityType = HKMapping.activityType(named: activityType)
        config.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []
        if let e = energyKcal, e > 0,
           store.authorizationStatus(for: HKQuantityType(.activeEnergyBurned)) == .sharingAuthorized {
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: e),
                                            start: start, end: end, metadata: baseMetadata()))
        }
        if let d = distanceMeters, d > 0 {
            let distType: HKQuantityType = config.activityType == .cycling ? HKQuantityType(.distanceCycling)
                : (config.activityType == .swimming ? HKQuantityType(.distanceSwimming) : HKQuantityType(.distanceWalkingRunning))
            if store.authorizationStatus(for: distType) == .sharingAuthorized {
                samples.append(HKQuantitySample(type: distType, quantity: HKQuantity(unit: .meter(), doubleValue: d),
                                                start: start, end: end, metadata: baseMetadata()))
            }
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }
        var meta = baseMetadata()
        if !sets.isEmpty { meta[WorkoutInfo.setsKey] = ExerciseSet.encode(sets) }
        try await builder.addMetadata(meta)
        try await builder.endCollection(at: end)
        guard let workout = try await builder.finishWorkout() else { throw HealthWriteError.unsupported("workout") }
        return workout.uuid.uuidString
    }

    // MARK: Category entries

    @discardableResult
    public func logMindful(start: Date, minutes: Double) async throws -> String {
        let type = HKCategoryType(.mindfulSession)
        try ensureAuthorized(type, "mindful minutes")
        let s = HKCategorySample(type: type, value: HKCategoryValue.notApplicable.rawValue, start: start,
                                 end: start.addingTimeInterval(minutes * 60), metadata: baseMetadata())
        try await store.save(s)
        return s.uuid.uuidString
    }

    @discardableResult
    public func logSleep(bedtime: Date, wake: Date) async throws -> String {
        let type = HKCategoryType(.sleepAnalysis)
        try ensureAuthorized(type, "sleep")
        let s = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                                 start: bedtime, end: wake, metadata: baseMetadata())
        try await store.save(s)
        return s.uuid.uuidString
    }

    // MARK: Delete

    /// Deletes an entry this app wrote (HealthKit only allows deleting your
    /// own objects). Correlations delete their component samples too.
    public func delete(id: String, metric: MetricID) async throws {
        guard let uuid = UUID(uuidString: id), let m = MetricRegistry.type(metric) else { throw HealthWriteError.notFound }
        let pred = HKQuery.predicateForObject(with: uuid)
        var types: [HKSampleType] = []
        if [.dietaryEnergy, .protein, .carbohydrates, .fat].contains(metric) { types.append(HKCorrelationType(.food)) }
        if [.bloodPressureSystolic, .bloodPressureDiastolic].contains(metric) { types.append(HKCorrelationType(.bloodPressure)) }
        if let t = HKMapping.sampleType(for: m) { types.append(t) }
        for t in types {
            if let obj = try await store.samples(of: t, predicate: pred, limit: 1).first {
                if let c = obj as? HKCorrelation { try await store.delete(Array(c.objects) + [c]) } else { try await store.delete(obj) }
                return
            }
        }
        throw HealthWriteError.notFound
    }
}
