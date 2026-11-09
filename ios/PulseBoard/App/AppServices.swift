import Foundation
import Observation
import SwiftData
import BackgroundTasks
import PulseCore
import PulseKit

/// Composition root. Owns every service and wires them together. Views get
/// it from the environment; nothing else holds global state.
@MainActor
@Observable
final class AppServices {
    static let shared = AppServices()

    let provider: HealthKitProvider
    let healthContainer: ModelContainer
    let store: LocalStore
    let ingestionStatus: IngestionStatus
    let ingestion: IngestionEngine
    let settings: SettingsStore
    let entitlements: EntitlementManager
    let writer: HealthWriter
    let scoreService: ScoreService
    let insights: InsightsService
    let phraser = InsightPhraser()
    let ai = AIAvailability()
    let challenges: MockChallengeService
    let challengeData: ChallengeDataSource
    let calendar: Calendar
    /// Today's scores (observed by the dashboard).
    var todayScores: [ScoreKind: ScoreResult] = [:]

    private var observersStarted = false

    private init() {
        PulseKitConfig.bootstrap()
        calendar = .pulse()
        provider = HealthKitProvider()
        do {
            healthContainer = try HealthCache.makeContainer()
        } catch {
            // A corrupt cache is recoverable: everything can be re-read from HealthKit.
            healthContainer = try! HealthCache.makeContainer(inMemory: true)
        }
        store = HealthCache.makeStore(healthContainer)
        ingestionStatus = IngestionStatus()
        ingestion = IngestionEngine(provider: provider, store: store, status: ingestionStatus, calendar: calendar)
        let settingsStore = SettingsStore(cloudKitContainer: PulseKitConfig.iCloudContainer)
        settings = settingsStore
        entitlements = EntitlementManager()
        writer = HealthWriter(store: provider.store)
        scoreService = ScoreService(provider: provider, store: store, calendar: calendar)
        insights = InsightsService(store: store, scores: scoreService, calendar: calendar)
        challengeData = ChallengeDataSource(provider: provider, store: store, calendar: calendar)
        // Challenge configs (memberships, custom challenges) sync as settings;
        // submitted scores are never persisted to iCloud.
        // TODO(server-sync): replace MockChallengeService with ServerChallengeService.
        var mockState = settingsStore.challengeConfig(MockChallengeService.State.self, id: "state") ?? .init()
        mockState.submitted = []
        let cal = calendar
        let settingsRef = settingsStore
        challenges = MockChallengeService(state: mockState, today: { DayKey(Date(), calendar: cal) }, persist: { state in
            var s = state
            s.submitted = []
            Task { @MainActor in settingsRef.saveChallengeConfig(s, id: "state") }
        })

        let settings = self.settings
        let ingestion = self.ingestion
        Task {
            await ingestion.configure(preferredSources: settings.preferredSources, priority: settings.sourcePriority)
            await ingestion.setDataChangedHandler { days, metrics in
                await AppServices.shared.afterDataChange(days: days, metrics: metrics)
            }
        }
    }

    // MARK: Lifecycle

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingComplete") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingComplete") }
    }

    /// Called from didFinishLaunching (also for background launches).
    nonisolated func startObserversIfAuthorized() {
        Task { @MainActor in
            guard self.hasCompletedOnboarding, !self.observersStarted else { return }
            self.observersStarted = true
            await self.ingestion.startObservers()
        }
    }

    func requestHealthAccess() async throws {
        ingestionStatus.phase = .authorizing
        let all = MetricRegistry.all.map(\.id)
        let writable = MetricRegistry.writable.map(\.id)
        try await provider.requestAuthorization(read: all, write: writable)
        hasCompletedOnboarding = true
        startObserversIfAuthorized()
        await ingestion.startBackfill()
        Self.scheduleBackgroundWork()
    }

    func didBecomeActive() {
        // Apple Intelligence can be turned on (or finish downloading) at any time.
        ai.refresh()
        guard hasCompletedOnboarding else { return }
        Task {
            await ingestion.configure(preferredSources: settings.preferredSources, priority: settings.sourcePriority)
            await ingestion.startBackfill()   // resumes if incomplete; no-op otherwise
            await ingestion.refreshAll()
            await afterDataChange()
        }
    }

    func didEnterBackground() {
        Self.scheduleBackgroundWork()
    }

    /// Hook for everything that depends on cached data: derived scores
    /// (Milestone 6), widget snapshot (Milestone 4), watch sync (Milestone 11).
    func afterDataChange(days: Set<DayKey> = [], metrics: Set<MetricID> = []) async {
        let scoreInputs: Set<MetricID> = [.hrv, .restingHeartRate, .sleep, .heartRate, .steps, .workout]
        let today = DayKey.today(calendar)
        if !days.isEmpty && (metrics.isEmpty || !metrics.isDisjoint(with: scoreInputs)) {
            // Sleep/HRV changes affect the following day's scores too.
            await scoreService.invalidate(days.union(days.map { $0.addingDays(1) }))
        }
        await refreshScores(force: days.contains(today) || metrics.isEmpty)
        if !days.isEmpty { await insights.invalidate() }
        let widgetScores = [ScoreKind.readiness, .sleep, .strain, .energy].compactMap { k -> WidgetSnapshot.Score? in
            guard let r = todayScores[k] else { return nil }
            return WidgetSnapshot.Score(kind: k.rawValue, value: r.value, label: r.label, isEstimated: r.isEstimated)
        }
        await challengeData.invalidate(days)
        await WidgetSnapshotWriter.write(services: self, scores: widgetScores, challenge: await topChallengeStanding())
    }

    /// Best-ranked joined, active challenge (for widgets and the watch).
    func topChallengeStanding() async -> WidgetSnapshot.ChallengeStanding? {
        let today = DayKey.today(calendar)
        guard let joined = try? await challenges.joined() else { return nil }
        var best: WidgetSnapshot.ChallengeStanding?
        for c in joined where c.isActive(on: today) {
            let daily = await challengeData.dailyValues(c, today: today)
            guard let lb = try? await challenges.leaderboard(for: c, myDaily: daily, today: today),
                  let me = lb.first(where: \.isCurrentUser) else { continue }
            if best == nil || me.rank < best!.rank {
                best = .init(title: c.title, rank: me.rank, participants: lb.count, score: me.score)
            }
        }
        return best
    }

    func refreshScores(force: Bool = false) async {
        await scoreService.configure(preferredSources: settings.preferredSources, priority: settings.sourcePriority,
                                     sleepGoalMinutes: settings.preferences.sleepGoalMinutes)
        todayScores = await scoreService.scores(for: DayKey.today(calendar), force: force)
    }

    /// Changing a metric's preferred source recomputes its history.
    func setPreferredSource(_ key: String?, for metric: MetricID) {
        settings.setPreferredSource(key, for: metric)
        Task {
            await ingestion.configure(preferredSources: settings.preferredSources, priority: settings.sourcePriority)
            await ingestion.rebuild(metric)
        }
    }

    /// After a manual write: pull it back through the normal ingestion path
    /// (so it is normalized, tagged isManual and aggregated like any sample).
    func didWrite(_ metrics: [MetricID]) async {
        for id in metrics {
            if let m = MetricRegistry.type(id) { await ingestion.syncIncremental(m) }
        }
    }

    /// Custom metrics are local-only: write straight to the cache.
    func logCustom(_ def: CustomMetricDefinition, value: Double, at date: Date) async {
        try? await store.upsert([def.sample(value: value, date: date)])
        let day = DayKey(date, calendar: calendar)
        let samples = (try? await store.samples(def.metricID, from: day.date(calendar), to: day.addingDays(1).date(calendar))) ?? []
        let rows = Aggregator.daily(def.metricType, samples: samples, options: .init(calendar: calendar))
        try? await store.upsert(rows)
        ingestionStatus.dataRevision += 1
    }

    nonisolated static func scheduleBackgroundWork() {
        let backfill = BGProcessingTaskRequest(identifier: PulseKitConfig.backfillTaskIdentifier)
        backfill.requiresNetworkConnectivity = false
        backfill.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(backfill)

        let refresh = BGAppRefreshTaskRequest(identifier: PulseKitConfig.refreshTaskIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(refresh)
    }

    /// Wipes the local cache (HealthKit data is untouched) and re-imports.
    func resetCache() async {
        await ingestion.cancelBackfill()
        try? await store.resetAll()
        ingestionStatus.progress = 0
        await ingestion.startBackfill()
    }
}
