import Foundation
import HealthKit
import PulseCore

/// Orchestrates HealthKit → local cache ingestion:
/// - first-launch chunked, resumable backfill (newest data first)
/// - HKObserverQuery + anchored queries + background delivery for updates
/// - aggregation tables (hour/day/week/month/year)
///
/// Battery: work is batched per metric/chunk; only dirty days are
/// recomputed; hourly rows are pruned after `hourlyWindowDays`.
public actor IngestionEngine {
    public static let recentWindowDays = 30
    public static let hourlyWindowDays = 120
    /// Metrics whose hourly aggregates power intraday (Day) charts.
    public static let hourlyMetrics: Set<MetricID> = [.steps, .activeEnergy, .heartRate, .distanceWalkingRunning, .exerciseTime]

    let provider: HealthKitProvider
    let store: LocalStore
    let status: IngestionStatus
    var calendar: Calendar
    var preferredSources: [MetricID: String] = [:]
    var priority: SourcePriority = .default
    var observerQueries: [HKObserverQuery] = []
    var backfillTask: Task<Void, Never>?
    /// Called with days whose data changed (score recompute, widget refresh).
    var onDataChanged: (@Sendable (Set<DayKey>, Set<MetricID>) async -> Void)?

    public init(provider: HealthKitProvider, store: LocalStore, status: IngestionStatus, calendar: Calendar = .pulse()) {
        self.provider = provider
        self.store = store
        self.status = status
        self.calendar = calendar
    }

    public func setDataChangedHandler(_ h: @escaping @Sendable (Set<DayKey>, Set<MetricID>) async -> Void) {
        onDataChanged = h
    }

    public func configure(preferredSources: [MetricID: String], priority: SourcePriority) {
        self.preferredSources = preferredSources
        self.priority = priority
    }

    /// Ordered by importance so the dashboard fills in core cards first.
    var orderedMetrics: [MetricType] {
        let core: [MetricID] = [.steps, .activeEnergy, .exerciseTime, .sleep, .restingHeartRate, .hrv, .heartRate,
                                .workout, .bodyMass, .dietaryEnergy, .water]
        let rest = MetricRegistry.all.map(\.id).filter { !core.contains($0) }
        return (core + rest).compactMap(MetricRegistry.type).filter { HKMapping.objectType(for: $0) != nil }
    }

    // MARK: Backfill

    /// Starts (or resumes) the backfill. Safe to call repeatedly; returns
    /// immediately if one is already running.
    public func startBackfill() {
        guard backfillTask == nil else { return }
        backfillTask = Task { [weak self] in
            await self?.runBackfill()
            await self?.clearTask()
        }
    }

    func clearTask() { backfillTask = nil }

    public func cancelBackfill() {
        backfillTask?.cancel()
        backfillTask = nil
    }

    /// Runs until done or cancelled (e.g. BGProcessingTask expiration).
    public func runBackfill() async {
        let metrics = orderedMetrics
        let now = Date()
        var oldest: [MetricID: Date] = [:]
        for m in metrics { oldest[m.id] = await oldestSampleDate(m) }

        // Phase 1: the most recent 30 days for every metric.
        await setPhase(.recent)
        let recentStart = calendar.date(byAdding: .day, value: -Self.recentWindowDays, to: calendar.startOfDay(for: now))!
        for m in metrics {
            if Task.isCancelled { return await setPhase(.paused) }
            let state = (try? await store.syncState(m.id)) ?? (nil, nil, false)
            if state.complete || state.backfilledFrom != nil { continue }
            guard let first = oldest[m.id] else {
                try? await store.updateSyncState(m.id, backfilledFrom: .some(now), complete: true)
                continue
            }
            await setCurrent(m.displayName)
            let start = max(recentStart, first)
            do {
                try await ingest(m, interval: DateInterval(start: start, end: now))
                try await store.updateSyncState(m.id, backfilledFrom: .some(start), complete: start <= first)
            } catch {
                if await handle(error) { return }
            }
            await updateProgress(metrics, oldest: oldest, now: now)
        }

        // Phase 2: walk backwards through history, round-robin across metrics.
        await setPhase(.history)
        var remaining = true
        while remaining {
            remaining = false
            for m in metrics {
                if Task.isCancelled { return await setPhase(.paused) }
                guard let first = oldest[m.id] else { continue }
                let state = (try? await store.syncState(m.id)) ?? (nil, nil, false)
                if state.complete { continue }
                let end = state.backfilledFrom ?? now
                if end <= first {
                    try? await store.updateSyncState(m.id, complete: true)
                    continue
                }
                remaining = true
                await setCurrent(m.displayName)
                let chunkDays = (m.kind == .cumulative || m.kind == .discrete) ? 365 : 120
                let start = max(first, calendar.date(byAdding: .day, value: -chunkDays, to: end)!)
                do {
                    try await ingest(m, interval: DateInterval(start: start, end: end))
                    try await store.updateSyncState(m.id, backfilledFrom: .some(start), complete: start <= first)
                } catch {
                    if await handle(error) { return }
                }
                await updateProgress(metrics, oldest: oldest, now: now)
            }
        }
        try? await store.pruneHourly(olderThan: DayKey(now, calendar: calendar).addingDays(-Self.hourlyWindowDays))
        await setPhase(.complete)
    }

    /// Returns true if backfill should stop (e.g. device locked).
    func handle(_ error: Error) async -> Bool {
        let ns = error as NSError
        let locked = ns.domain == HKError.errorDomain && ns.code == HKError.Code.errorDatabaseInaccessible.rawValue
        await MainActor.run {
            status.lastError = locked ? "Health data is unavailable while your device is locked. Backfill resumes when you unlock." : error.localizedDescription
            if locked { status.phase = .paused }
        }
        return locked
    }

    func oldestSampleDate(_ m: MetricType) async -> Date? {
        guard let type = HKMapping.sampleType(for: m) else { return nil }
        let first = try? await provider.store.samples(of: type, predicate: nil, limit: 1, ascending: true)
        return first?.first?.startDate
    }

    // MARK: Ingest one interval

    /// Ingests `interval` for `metric`: raw samples (low-volume types) and
    /// aggregate tables. Returns affected days.
    @discardableResult
    func ingest(_ m: MetricType, interval: DateInterval) async throws -> Set<DayKey> {
        var affected = Set<DayKey>()
        let firstDay = DayKey(interval.start, calendar: calendar)
        let lastDay = DayKey(interval.end, calendar: calendar)
        affected.formUnion(DayKey.range(firstDay, through: lastDay))

        switch m.kind {
        case .cumulative, .discrete:
            if !m.isHighVolume {
                let samples = try await provider.samples(of: m.id, in: interval)
                try await store.upsert(samples)
            }
            let policy: SourcePolicy = preferredSources[m.id].map { .preferred($0) } ?? .merged
            let daily = try await provider.aggregates(of: m.id, in: interval, policy: policy, calendar: calendar, hourly: false)
            try await store.upsert(daily)
            if Self.hourlyMetrics.contains(m.id) {
                let hourlyStart = calendar.date(byAdding: .day, value: -Self.hourlyWindowDays, to: Date())!
                if interval.end > hourlyStart {
                    let hi = DateInterval(start: max(interval.start, hourlyStart), end: interval.end)
                    let hourly = try await provider.aggregates(of: m.id, in: hi, policy: policy, calendar: calendar, hourly: true)
                    try await store.upsert(hourly)
                }
            }
        case .category, .workout, .ecg:
            let samples = try await provider.samples(of: m.id, in: interval)
            try await store.upsert(samples)
            try await recomputeDaily(m, days: affected)
        }
        try await recomputeRollups(m, days: affected)
        return affected
    }

    /// Recomputes daily rows from cached raw samples (sample-based metrics).
    func recomputeDaily(_ m: MetricType, days: Set<DayKey>) async throws {
        guard let lo = days.min(), let hi = days.max() else { return }
        let from = lo.start(in: calendar)
        let to = hi.addingDays(1).start(in: calendar)
        // Sleep nights are keyed by wake day — include the previous evening.
        let samples = try await store.samples(m.id, from: from.addingTimeInterval(-12 * 3600), to: to)
        let opts = Aggregator.Options(priority: priority, preferredSource: preferredSources, calendar: calendar)
        let daily = Aggregator.daily(m, samples: samples, options: opts).filter { days.contains($0.day) }
        let present = Set(daily.map(\.day))
        try await store.deleteAggregates(m.id, period: .day, days: Array(days.subtracting(present)))
        try await store.upsert(daily)
    }

    func recomputeRollups(_ m: MetricType, days: Set<DayKey>) async throws {
        guard let lo = days.min(), let hi = days.max() else { return }
        for period in [DailyAggregate.Period.week, .month, .year] {
            let start: DayKey, end: DayKey
            switch period {
            case .week: start = lo.weekStart; end = hi.weekStart.addingDays(6)
            case .month: start = lo.monthStart; end = DayKey(year: hi.month == 12 ? hi.year + 1 : hi.year, month: hi.month == 12 ? 1 : hi.month + 1, day: 1).addingDays(-1)
            default: start = lo.yearStart; end = DayKey(year: hi.year, month: 12, day: 31)
            }
            let daily = try await store.aggregates(m.id, period: .day, from: start, to: end)
            try await store.upsert(Aggregator.rollup(daily, metric: m, to: period))
        }
    }

    // MARK: Incremental sync

    /// Registers observer queries + background delivery. Must be called early
    /// in `application(_:didFinishLaunchingWithOptions:)` so HealthKit can wake
    /// the app in the background.
    public func startObservers() async {
        guard observerQueries.isEmpty else { return }
        for (id, freq) in HKMapping.backgroundDelivery {
            guard let m = MetricRegistry.type(id), let type = HKMapping.sampleType(for: m) else { continue }
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                guard error == nil, let self else { completion(); return }
                Task {
                    await self.syncIncremental(m)
                    completion()
                }
            }
            provider.store.execute(q)
            observerQueries.append(q)
            try? await provider.store.enableBackgroundDelivery(for: type, frequency: freq)
        }
    }

    /// Foreground refresh of every metric (cheap: anchored deltas only).
    public func refreshAll() async {
        for m in orderedMetrics {
            if Task.isCancelled { return }
            await syncIncremental(m)
        }
        await MainActor.run { status.lastSync = Date() }
    }

    /// Anchored delta sync for one metric.
    public func syncIncremental(_ m: MetricType) async {
        do {
            let state = try await store.syncState(m.id)
            let anchor = state.anchor.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
            // Bound the first anchored query to a recent window; backfill covers history.
            let lookback = calendar.date(byAdding: .day, value: -(anchor == nil ? 2 : 14), to: Date())!
            let interval = DateInterval(start: lookback, end: .distantFuture)
            let (added, deleted, newAnchor) = try await provider.changes(of: m, since: anchor, interval: interval)

            var days = Set(added.flatMap { s in
                DayKey.range(DayKey(s.start, calendar: calendar), through: DayKey(s.end, calendar: calendar))
            })
            if m.id == .sleep { days.formUnion(days.map { $0.addingDays(1) }) }
            if !deleted.isEmpty {
                let removed = try await store.deleteSamples(ids: deleted)
                days.formUnion(removed.map { DayKey($0.start, calendar: calendar) })
                // High-volume types aren't cached raw: recompute the recent week.
                if m.isHighVolume || removed.count < deleted.count {
                    let today = DayKey(Date(), calendar: calendar)
                    days.formUnion(DayKey.range(today.addingDays(-7), through: today))
                }
            }
            if let newAnchor, let data = try? NSKeyedArchiver.archivedData(withRootObject: newAnchor, requiringSecureCoding: true) {
                try await store.updateSyncState(m.id, anchor: .some(data))
            }
            guard !days.isEmpty else { return }

            if m.kind == .cumulative || m.kind == .discrete {
                if !m.isHighVolume { try await store.upsert(added) }
                for d in days.sorted() {
                    let iv = d.interval(in: calendar)
                    try await ingestQuantityDay(m, interval: iv)
                }
                try await recomputeRollups(m, days: days)
            } else {
                try await store.upsert(added)
                try await recomputeDaily(m, days: days)
                try await recomputeRollups(m, days: days)
            }
            await notifyChanged(days, [m.id])
        } catch {
            _ = await handle(error)
        }
    }

    func ingestQuantityDay(_ m: MetricType, interval: DateInterval) async throws {
        let policy: SourcePolicy = preferredSources[m.id].map { .preferred($0) } ?? .merged
        let daily = try await provider.aggregates(of: m.id, in: interval, policy: policy, calendar: calendar, hourly: false)
        let day = DayKey(interval.start, calendar: calendar)
        if daily.isEmpty { try await store.deleteAggregates(m.id, period: .day, days: [day]) }
        try await store.upsert(daily)
        if Self.hourlyMetrics.contains(m.id) {
            try await store.deleteAggregates(m.id, period: .hour, days: [day])
            try await store.upsert(try await provider.aggregates(of: m.id, in: interval, policy: policy, calendar: calendar, hourly: true))
        }
    }

    /// Recompute a metric fully (after the user changes its preferred source).
    public func rebuild(_ metric: MetricID) async {
        guard let m = MetricRegistry.type(metric) else { return }
        try? await store.updateSyncState(metric, backfilledFrom: .some(nil), complete: false)
        let now = Date()
        guard let first = await oldestSampleDate(m) else { return }
        var end = now
        while end > first {
            let start = max(first, calendar.date(byAdding: .day, value: -365, to: end)!)
            do { try await ingest(m, interval: DateInterval(start: start, end: end)) } catch { break }
            end = start
        }
        try? await store.updateSyncState(metric, backfilledFrom: .some(first), complete: true)
        await notifyChanged(Set(DayKey.range(DayKey(now, calendar: calendar).addingDays(-60), through: DayKey(now, calendar: calendar))), [metric])
    }

    func notifyChanged(_ days: Set<DayKey>, _ metrics: Set<MetricID>) async {
        await MainActor.run { status.dataRevision += 1 }
        if let onDataChanged { await onDataChanged(days, metrics) }
    }

    // MARK: Status helpers

    func setPhase(_ p: IngestionStatus.Phase) async {
        await MainActor.run {
            status.phase = p
            if p == .complete { status.progress = 1; status.currentMetric = nil }
            status.dataRevision += 1
        }
    }

    func setCurrent(_ name: String) async {
        await MainActor.run { status.currentMetric = name }
    }

    func updateProgress(_ metrics: [MetricType], oldest: [MetricID: Date], now: Date) async {
        var total = 0.0, n = 0.0
        var minDate = now
        for m in metrics {
            guard let first = oldest[m.id] else { continue }
            let state = (try? await store.syncState(m.id)) ?? (nil, nil, false)
            let span = max(1, now.timeIntervalSince(first))
            let from = state.backfilledFrom ?? now
            minDate = min(minDate, from)
            total += state.complete ? 1 : min(1, now.timeIntervalSince(from) / span)
            n += 1
        }
        let p = n > 0 ? total / n : 1
        let oldestIngested = minDate
        await MainActor.run {
            status.progress = p
            status.oldestIngested = oldestIngested
            status.dataRevision += 1
        }
    }
}
