import Foundation
import SwiftData
import PulseCore

/// Factory for the local-only health cache container.
public enum HealthCache {
    public static let schema = Schema([SampleRecord.self, AggregateRecord.self, ScoreRecord.self,
                                       SyncStateRecord.self, CustomMetricRecord.self, FoodLogRecord.self])

    /// IMPORTANT: `cloudKitDatabase: .none`. When the app has the iCloud
    /// entitlement, SwiftData's default (`.automatic`) would mirror this store
    /// to CloudKit — which would violate guideline 5.1.3(ii).
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration("HealthCache", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let dir = URL.applicationSupportDirectory.appending(path: "HealthCache", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            config = ModelConfiguration("HealthCache", schema: schema, url: dir.appending(path: "health.store"),
                                        cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [config])
    }
}

/// Background actor for all health-cache reads/writes. Never touch
/// SampleRecord/AggregateRecord from the main thread for bulk work.
@ModelActor
public actor LocalStore {
    // MARK: Samples

    public func upsert(_ samples: [Sample]) throws {
        guard !samples.isEmpty else { return }
        // @Attribute(.unique) on id makes insert an upsert.
        for s in samples { modelContext.insert(SampleRecord(s)) }
        try modelContext.save()
    }

    public func deleteSamples(ids: [String]) throws -> [Sample] {
        guard !ids.isEmpty else { return [] }
        let idSet = ids
        let fd = FetchDescriptor<SampleRecord>(predicate: #Predicate { idSet.contains($0.id) })
        let found = try modelContext.fetch(fd)
        let removed = found.map(\.sample)
        for r in found { modelContext.delete(r) }
        try modelContext.save()
        return removed
    }

    public func samples(_ metric: MetricID, from: Date, to: Date) throws -> [Sample] {
        let t = metric.rawValue
        // Include samples that started up to 1 day before `from` (sleep sessions
        // and workouts that straddle the boundary).
        let lower = from.addingTimeInterval(-86_400)
        let fd = FetchDescriptor<SampleRecord>(
            predicate: #Predicate { $0.type == t && $0.start >= lower && $0.start < to },
            sortBy: [SortDescriptor(\.start)])
        return try modelContext.fetch(fd).map(\.sample).filter { $0.end > from || $0.start >= from }
    }

    public func manualSamples(limit: Int = 50) throws -> [Sample] {
        var fd = FetchDescriptor<SampleRecord>(predicate: #Predicate { $0.isManual == true },
                                               sortBy: [SortDescriptor(\.start, order: .reverse)])
        fd.fetchLimit = limit
        return try modelContext.fetch(fd).map(\.sample)
    }

    public func sampleCount(_ metric: MetricID) throws -> Int {
        let t = metric.rawValue
        return try modelContext.fetchCount(FetchDescriptor<SampleRecord>(predicate: #Predicate { $0.type == t }))
    }

    // MARK: Aggregates

    public func upsert(_ aggregates: [DailyAggregate]) throws {
        guard !aggregates.isEmpty else { return }
        for a in aggregates { modelContext.insert(AggregateRecord(a)) }
        try modelContext.save()
    }

    public func aggregates(_ metric: MetricID, period: DailyAggregate.Period, from: DayKey, to: DayKey) throws -> [DailyAggregate] {
        let m = metric.rawValue, p = period.rawValue, lo = from.julianDay, hi = to.julianDay
        let fd = FetchDescriptor<AggregateRecord>(
            predicate: #Predicate { $0.metric == m && $0.period == p && $0.dayIndex >= lo && $0.dayIndex <= hi },
            sortBy: [SortDescriptor(\.dayIndex), SortDescriptor(\.hour)])
        return try modelContext.fetch(fd).map(\.aggregate)
    }

    /// Latest daily row per metric (for "today" cards).
    public func latestAggregate(_ metric: MetricID) throws -> DailyAggregate? {
        let m = metric.rawValue, p = DailyAggregate.Period.day.rawValue
        var fd = FetchDescriptor<AggregateRecord>(predicate: #Predicate { $0.metric == m && $0.period == p },
                                                  sortBy: [SortDescriptor(\.dayIndex, order: .reverse)])
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first.map(\.aggregate)
    }

    public func deleteAggregates(_ metric: MetricID, period: DailyAggregate.Period, days: [DayKey]) throws {
        let m = metric.rawValue, p = period.rawValue, idx = days.map(\.julianDay)
        try modelContext.delete(model: AggregateRecord.self,
                                where: #Predicate { $0.metric == m && $0.period == p && idx.contains($0.dayIndex) })
        try modelContext.save()
    }

    public func earliestAggregateDay(_ metric: MetricID) throws -> DayKey? {
        let m = metric.rawValue, p = DailyAggregate.Period.day.rawValue
        var fd = FetchDescriptor<AggregateRecord>(predicate: #Predicate { $0.metric == m && $0.period == p },
                                                  sortBy: [SortDescriptor(\.dayIndex)])
        fd.fetchLimit = 1
        return try modelContext.fetch(fd).first.map { DayKey(julianDay: $0.dayIndex) }
    }

    /// Hourly aggregates are only kept for the recent window (intraday charts,
    /// Energy model). Older hourly rows are pruned to bound storage.
    public func pruneHourly(olderThan day: DayKey) throws {
        let p = DailyAggregate.Period.hour.rawValue, lo = day.julianDay
        try modelContext.delete(model: AggregateRecord.self, where: #Predicate { $0.period == p && $0.dayIndex < lo })
        try modelContext.save()
    }

    // MARK: Scores

    public func saveScore<T: Encodable>(_ kind: String, day: DayKey, value: T) throws {
        let data = try JSONEncoder().encode(value)
        modelContext.insert(ScoreRecord(kind: kind, day: day, payload: data))
        try modelContext.save()
    }

    public func scores<T: Decodable>(_ kind: String, from: DayKey, to: DayKey, as: T.Type) throws -> [DayKey: T] {
        let lo = from.julianDay, hi = to.julianDay
        let fd = FetchDescriptor<ScoreRecord>(predicate: #Predicate { $0.kind == kind && $0.dayIndex >= lo && $0.dayIndex <= hi })
        var out: [DayKey: T] = [:]
        for r in try modelContext.fetch(fd) {
            if let v = try? JSONDecoder().decode(T.self, from: r.payload) { out[DayKey(julianDay: r.dayIndex)] = v }
        }
        return out
    }

    public func invalidateScores(days: Set<DayKey>) throws {
        let idx = days.map(\.julianDay)
        try modelContext.delete(model: ScoreRecord.self, where: #Predicate { idx.contains($0.dayIndex) })
        try modelContext.save()
    }

    // MARK: Sync state

    public func syncState(_ metric: MetricID) throws -> (anchor: Data?, backfilledFrom: Date?, complete: Bool) {
        let m = metric.rawValue
        let r = try modelContext.fetch(FetchDescriptor<SyncStateRecord>(predicate: #Predicate { $0.metric == m })).first
        return (r?.anchorData, r?.backfilledFrom, r?.backfillComplete ?? false)
    }

    public func updateSyncState(_ metric: MetricID, anchor: Data?? = nil, backfilledFrom: Date?? = nil, complete: Bool? = nil) throws {
        let m = metric.rawValue
        let r = try modelContext.fetch(FetchDescriptor<SyncStateRecord>(predicate: #Predicate { $0.metric == m })).first
            ?? { let n = SyncStateRecord(metric: m); modelContext.insert(n); return n }()
        if let anchor { r.anchorData = anchor }
        if let backfilledFrom { r.backfilledFrom = backfilledFrom }
        if let complete { r.backfillComplete = complete }
        r.lastSync = Date()
        try modelContext.save()
    }

    public func resetAll() throws {
        try modelContext.delete(model: SampleRecord.self)
        try modelContext.delete(model: AggregateRecord.self)
        try modelContext.delete(model: ScoreRecord.self)
        try modelContext.delete(model: SyncStateRecord.self)
        try modelContext.save()
    }

    // MARK: Custom metrics (local-only)

    public func customMetrics() throws -> [CustomMetricDefinition] {
        try modelContext.fetch(FetchDescriptor<CustomMetricRecord>(sortBy: [SortDescriptor(\.createdAt)])).map {
            CustomMetricDefinition(id: $0.id, name: $0.name, unitLabel: $0.unitLabel, symbol: $0.symbol, aggregation: $0.aggregation)
        }
    }

    public func addCustomMetric(_ d: CustomMetricDefinition) throws {
        modelContext.insert(CustomMetricRecord(id: d.id, name: d.name, unitLabel: d.unitLabel, symbol: d.symbol, aggregation: d.aggregation))
        try modelContext.save()
    }

    public func deleteCustomMetric(id: String) throws {
        try modelContext.delete(model: CustomMetricRecord.self, where: #Predicate { $0.id == id })
        let t = MetricID.custom(id).rawValue
        try modelContext.delete(model: SampleRecord.self, where: #Predicate { $0.type == t })
        try modelContext.save()
    }

    // MARK: Food log (recent foods index)

    public func addFoodLog(_ f: FoodEntry, healthKitId: String?) throws {
        modelContext.insert(FoodLogRecord(id: f.id, healthKitId: healthKitId, name: f.name, date: f.date, kcal: f.kcal,
                                          protein: f.protein, carbs: f.carbs, fat: f.fat, meal: f.meal.rawValue))
        try modelContext.save()
    }

    public func recentFoods(limit: Int = 30) throws -> [FoodEntry] {
        var fd = FetchDescriptor<FoodLogRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fd.fetchLimit = 200
        var seen = Set<String>()
        var out: [FoodEntry] = []
        for r in try modelContext.fetch(fd) where !seen.contains(r.name.lowercased()) {
            seen.insert(r.name.lowercased())
            out.append(FoodEntry(id: r.id, name: r.name, date: r.date, kcal: r.kcal, protein: r.protein, carbs: r.carbs,
                                 fat: r.fat, meal: MealSlot(rawValue: r.meal) ?? .snack))
            if out.count >= limit { break }
        }
        return out
    }

    public func foodLogs(from: Date, to: Date) throws -> [FoodEntry] {
        let fd = FetchDescriptor<FoodLogRecord>(predicate: #Predicate { $0.date >= from && $0.date < to },
                                                sortBy: [SortDescriptor(\.date)])
        return try modelContext.fetch(fd).map {
            FoodEntry(id: $0.id, name: $0.name, date: $0.date, kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs,
                      fat: $0.fat, meal: MealSlot(rawValue: $0.meal) ?? .snack)
        }
    }
}
