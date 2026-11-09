import Foundation
import CoreLocation
import HealthKit

/// async/await wrappers around callback-based HealthKit queries.
extension HKHealthStore {
    func samples(of type: HKSampleType, predicate: NSPredicate?, limit: Int = HKObjectQueryNoLimit,
                 ascending: Bool = false) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, results, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: results ?? []) }
            }
            execute(q)
        }
    }

    struct AnchoredResult {
        var added: [HKSample]
        var deleted: [HKDeletedObject]
        var anchor: HKQueryAnchor?
    }

    func anchoredChanges(of type: HKSampleType, predicate: NSPredicate?, anchor: HKQueryAnchor?,
                         limit: Int = HKObjectQueryNoLimit) async throws -> AnchoredResult {
        try await withCheckedThrowingContinuation { cont in
            let q = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: limit) { _, added, deleted, newAnchor, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: AnchoredResult(added: added ?? [], deleted: deleted ?? [], anchor: newAnchor)) }
            }
            execute(q)
        }
    }

    func statisticsCollection(of type: HKQuantityType, predicate: NSPredicate?, options: HKStatisticsOptions,
                              anchor: Date, interval: DateComponents) async throws -> HKStatisticsCollection {
        try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: options,
                                                anchorDate: anchor, intervalComponents: interval)
            q.initialResultsHandler = { _, collection, error in
                if let error { cont.resume(throwing: error) }
                else if let collection { cont.resume(returning: collection) }
                else { cont.resume(throwing: HKError(.errorNoData)) }
            }
            execute(q)
        }
    }

    func sources(for type: HKSampleType) async throws -> Set<HKSource> {
        try await withCheckedThrowingContinuation { cont in
            let q = HKSourceQuery(sampleType: type, samplePredicate: nil) { _, sources, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: sources ?? []) }
            }
            execute(q)
        }
    }

    func activitySummaries(from: DateComponents, to: DateComponents) async throws -> [HKActivitySummary] {
        try await withCheckedThrowingContinuation { cont in
            let pred = HKQuery.predicate(forActivitySummariesBetweenStart: from, end: to)
            let q = HKActivitySummaryQuery(predicate: pred) { _, summaries, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: summaries ?? []) }
            }
            execute(q)
        }
    }

    func workoutRoute(for workout: HKWorkout) async throws -> [CLLocationLike] {
        let routes = try await samples(of: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))
        var points: [CLLocationLike] = []
        for case let route as HKWorkoutRoute in routes {
            let chunk: [CLLocationLike] = try await withCheckedThrowingContinuation { cont in
                var acc: [CLLocationLike] = []
                let q = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    if let error { cont.resume(throwing: error); return }
                    acc += (locations ?? []).map { CLLocationLike(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, timestamp: $0.timestamp) }
                    if done { cont.resume(returning: acc) }
                }
                execute(q)
            }
            points += chunk
        }
        return points
    }
}

/// Minimal location point so callers needn't import CoreLocation.
public struct CLLocationLike: Sendable, Hashable {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: Date
}
