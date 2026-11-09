import Foundation

/// Merges duplicate workouts recorded by several devices/apps (e.g. a run
/// tracked by both Apple Watch and Garmin, or Strava re-uploading a Garmin
/// activity). Two workouts are duplicates when their overlap covers at least
/// `overlapThreshold` of the *shorter* one. The highest-priority source's
/// workout is kept; missing fields (energy, distance, HR, route) are filled
/// from the duplicates, and `mergedFrom` lists the dropped ids.
public enum WorkoutMerger {
    public static let overlapThreshold = 0.5

    public static func merge(_ workouts: [Sample], priority: SourcePriority) -> [Sample] {
        let sorted = workouts.filter { $0.type == .workout }.sorted { $0.start < $1.start }
        var clusters: [[Sample]] = []
        for w in sorted {
            if let idx = clusters.lastIndex(where: { cluster in cluster.contains { isDuplicate($0, w) } }) {
                clusters[idx].append(w)
            } else {
                clusters.append([w])
            }
        }
        return clusters.map { cluster in
            guard cluster.count > 1 else { return cluster[0] }
            let ranked = cluster.sorted { priority.isHigher($0.source, $0.device, than: $1.source, $1.device) }
            var keep = ranked[0]
            var meta = keep.metadata ?? [:]
            for other in ranked.dropFirst() {
                for key in [WorkoutInfo.energyKey, WorkoutInfo.distanceKey, WorkoutInfo.avgHRKey, WorkoutInfo.hasRouteKey] where meta[key] == nil {
                    if let v = other.metadata?[key] { meta[key] = v }
                }
            }
            meta[WorkoutInfo.mergedFromKey] = ranked.dropFirst().map(\.id).joined(separator: ",")
            keep.metadata = meta
            // A merged workout counts as manual only if every copy was manual.
            keep.isManual = cluster.allSatisfy(\.isManual)
            return keep
        }
    }

    public static func isDuplicate(_ a: Sample, _ b: Sample) -> Bool {
        let overlap = min(a.end, b.end).timeIntervalSince(max(a.start, b.start))
        guard overlap > 0 else { return false }
        let shorter = min(a.duration, b.duration)
        guard shorter > 0 else { return false }
        return overlap / shorter >= overlapThreshold
    }
}
