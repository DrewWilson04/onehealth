import Foundation
import Observation
import PulseCore
import PulseKit

@MainActor
@Observable
final class GoalsModel {
    struct Row: Identifiable {
        let goal: Goal
        let metric: MetricType
        let streak: StreakInfo
        var id: String { goal.id }
    }
    var rows: [Row] = []

    func load(services: AppServices) async {
        let today = DayKey.today(services.calendar)
        var out: [Row] = []
        for g in services.settings.goals {
            guard let m = MetricRegistry.type(g.metric) else { continue }
            let rows = (try? await services.store.aggregates(g.metric, period: .day, from: today.addingDays(-400), to: today)) ?? []
            // Estimated (gap-filled) days never count toward streaks.
            let daily = Dictionary(rows.filter { !$0.isEstimated }.compactMap { r in r.value(for: m.dailyStatistic).map { (r.day, $0) } },
                                   uniquingKeysWith: { a, _ in a })
            out.append(Row(goal: g, metric: m, streak: Streaks.compute(goal: g, metric: m, daily: daily, today: today)))
        }
        rows = out
    }
}
