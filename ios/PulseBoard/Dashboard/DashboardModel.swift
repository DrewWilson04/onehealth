import Foundation
import Observation
import PulseCore
import PulseKit

extension DayKey {
    func date(_ calendar: Calendar = .pulse(), hour: Int? = nil) -> Date {
        let s = start(in: calendar)
        guard let hour else { return s }
        return calendar.date(byAdding: .hour, value: hour, to: s) ?? s
    }
    static func today(_ calendar: Calendar = .pulse()) -> DayKey { DayKey(Date(), calendar: calendar) }
}

/// Loads everything the Today grid needs from the local cache in one pass.
@MainActor
@Observable
final class DashboardModel {
    struct MetricSnapshot: Equatable {
        var today: DailyAggregate?
        /// Most recent day with data (for "latest" metrics like weight).
        var latest: DailyAggregate?
        var week: [TrendPoint]
        var comparison: PeriodComparison?
    }

    var metrics: [MetricID: MetricSnapshot] = [:]
    var rings: ActivityRings?
    var lastNight: SleepNight?
    var limited: [DashboardSection: [MetricID]] = [:]
    var loaded = false
    var hasAnyData = false

    func load(services: AppServices, metricIDs: [MetricID]) async {
        let cal = services.calendar
        let today = DayKey.today(cal)
        var out: [MetricID: MetricSnapshot] = [:]
        for id in Set(metricIDs + [.steps, .sleep]) {
            guard let m = MetricRegistry.type(id) else { continue }
            let rows = (try? await services.store.aggregates(id, period: .day, from: today.addingDays(-13), to: today)) ?? []
            let latest = try? await services.store.latestAggregate(id)
            let week = Trends.points(rows.filter { $0.day >= today.addingDays(-6) }, metric: m)
            let cmp = Trends.compare(rows, metric: m, period: .week, today: today)
            out[id] = MetricSnapshot(today: rows.first { $0.day == today }, latest: latest, week: week,
                                     comparison: cmp.current == nil ? nil : cmp)
        }
        metrics = out
        hasAnyData = out.values.contains { $0.latest != nil }
        rings = try? await services.provider.activityRings(days: 1, calendar: cal)[today]
        let sleepSamples = (try? await services.store.samples(.sleep, from: today.addingDays(-1).date(cal).addingTimeInterval(-6 * 3600),
                                                              to: today.addingDays(1).date(cal))) ?? []
        lastNight = SleepMerger.nights(sleepSamples, priority: services.settings.sourcePriority.preferring(services.settings.preferredSources[.sleep]),
                                       calendar: cal).last { $0.day == today }
        loaded = true
    }

    func loadAccess(services: AppServices) async {
        limited = await services.provider.accessSummary().limitedSections()
    }
}
