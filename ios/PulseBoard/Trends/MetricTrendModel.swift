import Foundation
import Observation
import PulseCore
import PulseKit

@MainActor
@Observable
final class MetricTrendModel {
    let metric: MetricType
    var range: TrendRange = .week
    var points: [TrendPoint] = []
    var rolling: [TrendPoint] = []
    var summary: TrendSummary?
    var weekComparison: PeriodComparison?
    var monthComparison: PeriodComparison?
    var bests: [PersonalBest] = []
    var loading = true
    /// True when plotted values are per-day averages of a period bucket.
    var isPerDayAverage = false
    var windowLabel = ""

    init(metric: MetricType) { self.metric = metric }

    func load(services: AppServices) async {
        loading = true
        defer { loading = false }
        let cal = services.calendar
        let store = services.store
        let today = DayKey.today(cal)
        let earliest = try? await store.earliestAggregateDay(metric.id)
        let (from, to) = Trends.window(range, today: today, earliest: earliest)
        windowLabel = range == .day ? Fmt.day(today) : "\(Fmt.day(from)) – \(Fmt.day(to))"

        let daily = (try? await store.aggregates(metric.id, period: .day, from: from, to: to)) ?? []
        summary = Trends.summary(daily, metric: metric)

        switch range.bucket {
        case .hour:
            let hourly = (try? await store.aggregates(metric.id, period: .hour, from: today, to: today)) ?? []
            if hourly.isEmpty {
                // Low-volume metrics: plot the day's raw samples.
                let s = (try? await store.samples(metric.id, from: today.date(cal), to: today.addingDays(1).date(cal))) ?? []
                points = s.map { TrendPoint(day: today, hour: cal.component(.hour, from: $0.start), value: $0.value) }
            } else {
                points = Trends.points(hourly, metric: metric)
            }
            isPerDayAverage = false
        case .day:
            points = Trends.points(daily, metric: metric)
            isPerDayAverage = false
        default:
            let rows = (try? await store.aggregates(metric.id, period: range.bucket, from: from, to: to)) ?? []
            isPerDayAverage = [.sum, .durationMinutes, .count].contains(metric.dailyStatistic)
            points = Trends.rollupPoints(rows, metric: metric, perDayAverage: isPerDayAverage)
        }
        rolling = range == .month || range == .week ? Trends.rollingAverage(Trends.points(
            (try? await store.aggregates(metric.id, period: .day, from: from.addingDays(-6), to: to)) ?? [], metric: metric),
            window: 7).filter { $0.day >= from } : []

        // Comparisons and bests use full history (cheap: one row per day).
        let recent = (try? await store.aggregates(metric.id, period: .day, from: today.addingDays(-70), to: today)) ?? []
        weekComparison = Trends.compare(recent, metric: metric, period: .week, today: today)
        monthComparison = Trends.compare(recent, metric: metric, period: .month, today: today)
        if let e = earliest {
            let all = (try? await store.aggregates(metric.id, period: .day, from: e, to: today)) ?? []
            let weeks = (try? await store.aggregates(metric.id, period: .week, from: e, to: today)) ?? []
            let months = (try? await store.aggregates(metric.id, period: .month, from: e, to: today)) ?? []
            bests = Trends.personalBests(daily: all, weekly: weeks, monthly: months, metric: metric)
        }
    }
}
