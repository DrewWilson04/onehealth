import Foundation
import WidgetKit
import PulseCore
import PulseKit

/// Builds the App Group snapshot consumed by widgets and complications.
/// Throttled: at most every 10 minutes unless forced (battery).
@MainActor
enum WidgetSnapshotWriter {
    private static var lastWrite: Date = .distantPast

    static let widgetMetrics: [MetricID] = [.steps, .activeEnergy, .exerciseTime, .distanceWalkingRunning, .sleep,
                                            .restingHeartRate, .hrv, .bodyMass, .water, .dietaryEnergy]

    static func write(services: AppServices, scores: [WidgetSnapshot.Score] = [],
                      challenge: WidgetSnapshot.ChallengeStanding? = nil, force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastWrite) > 600 else { return }
        lastWrite = Date()
        let cal = services.calendar
        let today = DayKey.today(cal)
        let goals = GoalsModel()
        await goals.load(services: services)
        var metrics: [WidgetSnapshot.Metric] = []
        for id in widgetMetrics {
            guard let m = MetricRegistry.type(id) else { continue }
            let rows = (try? await services.store.aggregates(id, period: .day, from: today.addingDays(-6), to: today)) ?? []
            let todayRow = m.dailyStatistic == .latest ? (try? await services.store.latestAggregate(id)) : rows.first { $0.day == today }
            let v = todayRow?.value(for: m.dailyStatistic)
            let goalRow = goals.rows.first { $0.goal.metric == id && $0.goal.period == .day }
            metrics.append(.init(id: id.rawValue, title: m.displayName, value: v, formatted: Fmt.value(v, metric: m),
                                 symbol: m.symbol, section: m.section.rawValue, goal: goalRow?.goal.target,
                                 progress: goalRow?.streak.progress, streak: goalRow?.streak.current,
                                 week: Trends.points(rows, metric: m).map(\.value)))
        }
        let rings = try? await services.provider.activityRings(days: 1, calendar: cal)[today]
        let hr = (try? await services.store.aggregates(.heartRate, period: .hour, from: today, to: today))?.last?.average
        let existing = AppGroup.readSnapshot()
        let snap = WidgetSnapshot(generatedAt: Date(), day: today, isPro: services.entitlements.isEnabled(.homeScreenWidgets),
                                  metrics: metrics, rings: rings, scores: scores.isEmpty ? (existing?.scores ?? []) : scores,
                                  latestHeartRate: hr, challenge: challenge ?? existing?.challenge)
        AppGroup.writeSnapshot(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
