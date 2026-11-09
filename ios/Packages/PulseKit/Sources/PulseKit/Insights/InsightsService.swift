import Foundation
import PulseCore

/// Builds features from the local cache and runs the stats engine. Used by
/// the AI Insights screen and by trend views (anomaly / trend-change notes).
public actor InsightsService {
    let store: LocalStore
    let scores: ScoreService
    var calendar: Calendar
    private var cached: (day: DayKey, findings: [Finding])?

    public init(store: LocalStore, scores: ScoreService, calendar: Calendar = .pulse()) {
        self.store = store
        self.scores = scores
        self.calendar = calendar
    }

    public func invalidate() { cached = nil }

    public func findings(priority: SourcePriority = .default) async -> [Finding] {
        let today = DayKey(Date(), calendar: calendar)
        if let c = cached, c.day == today { return c.findings }
        let from = today.addingDays(-(InsightsEngine.Config().lookbackDays + 45))
        var daily: [MetricID: [DayKey: Double]] = [:]
        let metrics: [MetricID] = [.steps, .activeEnergy, .exerciseTime, .restingHeartRate, .hrv, .respiratoryRate,
                                   .wristTemperature, .bodyMass, .vo2Max, .caffeine]
        for id in metrics {
            guard let m = MetricRegistry.type(id) else { continue }
            let rows = (try? await store.aggregates(id, period: .day, from: from, to: today)) ?? []
            daily[id] = Dictionary(rows.filter { !$0.isEstimated }.compactMap { r in r.value(for: m.dailyStatistic).map { (r.day, $0) } },
                                   uniquingKeysWith: { a, _ in a })
        }
        let sleep = (try? await store.samples(.sleep, from: from.start(in: calendar), to: today.addingDays(1).start(in: calendar))) ?? []
        let nights = SleepMerger.nights(sleep, priority: priority, calendar: calendar)
        let workouts = WorkoutMerger.merge((try? await store.samples(.workout, from: from.start(in: calendar), to: today.addingDays(1).start(in: calendar))) ?? [], priority: priority)
        let readiness = await scores.history(.readiness, from: today.addingDays(-90), to: today)
        let scoreSeries: [ScoreKind: [DayKey: Double]] = [.readiness: Dictionary(readiness.filter { !$0.isEstimated }.compactMap { r in r.value.map { (r.day, $0) } }, uniquingKeysWith: { a, _ in a })]
        let features = InsightFeatures.build(daily: daily, nights: nights, workouts: workouts, scores: scoreSeries, calendar: calendar)
        let f = InsightsEngine.run(features, today: today)
        cached = (today, f)
        return f
    }
}
